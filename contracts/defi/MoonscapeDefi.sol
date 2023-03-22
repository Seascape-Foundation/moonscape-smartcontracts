pragma solidity 0.6.7;

import "./../openzeppelin/contracts/access/Ownable.sol";
import "./../openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../openzeppelin/contracts/math/SafeMath.sol";
import "./../openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./../openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./../nfts/SeascapeNft.sol";
import "./Stake.sol";

contract MoonscapeDefi is Stake, IERC721Receiver, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    SeascapeNft private nft; 

    uint256 private constant scaler = 10**18;

    address private constant dead = 0x000000000000000000000000000000000000dEaD;

    uint public sessionId;
    uint public stakeId;
    uint public typeId;
    address public verifier;

    struct Session {
        uint startTime; // session start time
        uint endTime;   // session end time
        bool active;    // check session is active or not
    }

    struct TokenStaking {
        uint sessionId;
        address stakeToken;   // staked token or nft address
        uint rewardPool;      // reward token number
        address rewardToken;  // reward token address
        bool burn;
        uint typePool;
    }

    mapping(uint => Session) public sessions;
    mapping(bytes32 => bool) public addedStakings;
    mapping(uint => TokenStaking) public tokenStakings;         //uint stakeId => TokenStaking
    mapping(bytes32 => uint) public keyToId;                    //bytes32 key(stakeKeyOf(sessionId,stakeId)  => stakeId
    mapping(bytes32 => mapping(address => bool)) public receiveBonus; //bytes32 key(stakeKeyOf(sessionId,stakeId)=> weallet address => bool
    mapping(uint256 => address) public changeToken;

    mapping(address => bool) public changeAllowed;
    mapping(address => uint) public nonce;

    event StartSession(uint indexed sessionId, uint startTime, uint endTime);
    event PauseSession(uint indexed sessionId);
    event ResumeSession(uint indexed sessionId);
    event AddStaking(uint indexed sessionId, uint indexed stakeId);
    event StakeToken(address indexed staker, uint indexed sessionId, uint stakeId, uint cityId, uint buildingId, uint indexed amount, uint nonce);
    event UnStakeToken(address indexed staker, uint indexed sessionId, uint stakeId, uint indexed amount);
    event ImportNft(address indexed staker, uint indexed sessionId, uint stakeId, uint cityId, uint buildingId, uint indexed scapeNftId, uint time, uint chainId);
    event ExportNft(address indexed staker, uint indexed sessionId, uint stakeId, uint indexed scapeNftId, uint time);
    event WithdrawAll(uint indexed sessionId, uint indexed stakeId, uint cityId, uint buildingId, uint amount, uint indexed bonusPercent, address staker, uint time);
    event GiveBonus(uint indexed sessionId,uint indexed stakeId, uint bonusPercent, address rewardToken, address indexed staker, uint time);
    event TokenBuyPack(uint indexed sessionId, uint typeId, uint amount, uint packId, address indexed staker, uint time);

    constructor (address _scapeNftAddress) public {
        require(_scapeNftAddress != address(0), "MoonscapeDefi: ScapeNft can't be zero address");

        nft = SeascapeNft(_scapeNftAddress);
    }

    /// @dev start a new session
    function startSession(uint _startTime, uint _endTime, address _verifier) external onlyOwner{
        require(validSessionTime(_startTime, _endTime), "MoonscapeDefi:  Invalid session time");
        require(_verifier != address(0), "MoonscapeDefi: Verifier can't be zero address");

        sessionId++;

        sessions[sessionId] = Session(_startTime, _endTime, true);
        verifier            = _verifier;

        emit StartSession(sessionId, _startTime, _endTime);
    }

    /// @dev pause session
    function pauseSession(uint _sessionId) external onlyOwner{
        Session storage session = sessions[_sessionId];

        require(session.active, "MoonscapeDefi: INACTIVE");

        session.active = false;

        emit PauseSession(_sessionId);
    }

    /// @dev resume session, make it active
    function resumeSession(uint _sessionId) external onlyOwner{
        Session storage session = sessions[_sessionId];

        require(session.endTime > 0 && !session.active, "MoonscapeDefi: ACTIVE");

        session.active = true;

        emit ResumeSession(_sessionId);
    }

    /// @dev add token staking to session
    function addTokenStaking(uint _sessionId, address stakeAddress, uint rewardPool, address rewardToken, bool _burn, uint _typePool) external onlyOwner{
        bytes32 key = keccak256(abi.encodePacked(_sessionId, stakeAddress, rewardToken));

        require(!addedStakings[key], "MoonscapeDefi: DUPLICATE_STAKING");

        addedStakings[key] = true;

        //burn = true, the nft will burn;
        tokenStakings[++stakeId] = TokenStaking(_sessionId, stakeAddress, rewardPool, rewardToken, _burn, _typePool);

        bytes32 stakeKey = stakeKeyOf(sessionId, stakeId);

        keyToId[stakeKey] = stakeId;

        Session memory session = sessions[_sessionId];

        newStakePeriod(
            stakeKey,
            session.startTime,
            session.endTime,
            rewardPool    
        );

        emit AddStaking(_sessionId, stakeId);
    }

    /// @dev stake tokens
    function stakeToken(uint _stakeId, uint _cityId, uint _buildingId, uint _amount, uint8 v, bytes32[2] calldata sig) external {
        TokenStaking storage tokenStaking = tokenStakings[_stakeId];

        // todo
        // validate the session id
        bytes32 stakeKey = stakeKeyOf(tokenStaking.sessionId, _stakeId);

        require(isActive(stakeKey), "MoonscapeDefi: session not active");

        //validate stake id
        require(_stakeId <= stakeId,"MoonscapeDefi: do not have this stakeId");

        {
            bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
            bytes32 message         = keccak256(abi.encodePacked(_stakeId, tokenStaking.sessionId, _cityId, _buildingId, nonce[msg.sender], msg.sender));
            bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
            address recover         = ecrecover(hash, v, sig[0], sig[1]);

            require(recover == verifier, "MoonscapeDefi: Verification failed about stakeToken");
        }

        nonce[msg.sender]++;

        deposit(stakeKey, msg.sender, _amount);

        IERC20 token = IERC20(tokenStaking.stakeToken);

        require(token.balanceOf(msg.sender) >= _amount, "MoonscapeDefi: Not enough token to stake");

        token.safeTransferFrom(msg.sender, address(this), _amount);

        emit StakeToken(msg.sender, tokenStaking.sessionId, _stakeId, _cityId, _buildingId, _amount, nonce[msg.sender]);
    }

    /// @dev claim rewards
    function claim(uint _sessionId, uint _stakeId)
        external
        returns(uint256)
    {
        bytes32 stakeKey = stakeKeyOf(_sessionId, _stakeId);

        require(isActive(stakeKey), "MoonscapeDefi: session is ended, only unstake");

        return reward(stakeKey, msg.sender);
    }

    /// @dev stake seascapeNft
    function importNft(uint _stakeId, uint _cityId, uint _buildingId, uint _scapeNftId, uint8 _v, bytes32[2] calldata sig) external {
        TokenStaking storage tokenStaking = tokenStakings[_stakeId];

        // validate the session id
        bytes32 stakeKey = stakeKeyOf(tokenStaking.sessionId, _stakeId);

        require(isActive(stakeKey), "MoonscapeDefi: session not active");

        //validate stake id
        require(_stakeId <= stakeId, "MoonscapeDefi: do not have this stakeId");

        uint chainId;   
        assembly {
            chainId := chainid()
        }

        require(nft.ownerOf(_scapeNftId) == msg.sender, "MoonscapeDefi: not owned");

        {
            bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
            bytes32 message         = keccak256(abi.encodePacked(tokenStaking.sessionId, _stakeId, _cityId, _buildingId, _scapeNftId, nonce[msg.sender], msg.sender));
            bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
            address recover         = ecrecover(hash, _v, sig[0], sig[1]);

            require(recover == verifier, "MoonscapeDefi: Verification failed about stakeNft");
        }

        nonce[msg.sender]++;

        nft.safeTransferFrom(msg.sender, dead, _scapeNftId);

        emit ImportNft(msg.sender, tokenStaking.sessionId, _stakeId, _cityId, _buildingId, _scapeNftId, block.timestamp, chainId);
    }


    /// @dev withdraw all
    function withdrawAll(uint _stakeId, uint _cityId, uint _buildingId, uint _amount, uint _bonusPercent, uint8 _v, bytes32 _r, bytes32 _s) external {
        TokenStaking storage tokenStaking = tokenStakings[_stakeId];
        Session storage session = sessions[tokenStaking.sessionId];

        if(block.timestamp > session.endTime) {
            require(verifyBonus(tokenStaking.sessionId, _stakeId, _cityId, _buildingId, _bonusPercent, _v, _r, _s));
            require(giveBonus(tokenStaking.sessionId, _stakeId, tokenStaking.rewardToken, _bonusPercent));
        }

        unStakeToken(tokenStaking.sessionId, _stakeId, _amount);

        emit WithdrawAll(tokenStaking.sessionId, _stakeId, _cityId, _buildingId, _amount, _bonusPercent, msg.sender, block.timestamp);
    }


    /// @dev unstake tokens
    function unStakeToken(uint _sessionId, uint _stakeId, uint _amount) public {
        TokenStaking storage tokenStaking = tokenStakings[_stakeId];

        bytes32 stakeKey = stakeKeyOf(_sessionId, _stakeId);

        withdraw(stakeKey, msg.sender, _amount);

        IERC20 token = IERC20(tokenStaking.stakeToken);

        token.safeTransfer(msg.sender, _amount);

        emit UnStakeToken(msg.sender, _sessionId, _stakeId, _amount);
    }

    /// @dev verify Bonus
    function verifyBonus(uint _sessionId, uint _stakeId, uint _cityId, uint _buildingId, uint _bonusPercent, uint8 _v, bytes32 _r, bytes32 _s) internal returns(bool) {

        bytes32 stakeKey = stakeKeyOf(_sessionId, _stakeId);

        require(receiveBonus[stakeKey][msg.sender] == false, "MoonscapeDefi: already rewarded");

        {
            bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
            bytes32 message         = keccak256(abi.encodePacked(_sessionId, _stakeId, _cityId, _buildingId, _bonusPercent, nonce[msg.sender], msg.sender));
            bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
            address recover         = ecrecover(hash, _v, _r, _s);

            require(recover == verifier, "MoonscapeDefi: Verification failed about getBonus");
        }

        nonce[msg.sender]++;

        return true;
    }


    /// @dev get bonus reward after session is ended
    function giveBonus(uint _sessionId, uint _stakeId, address _rewardToken, uint _bonusPercent) internal returns(bool) {

        bytes32 stakeKey = stakeKeyOf(_sessionId, _stakeId);

        IERC20 rewardToken = IERC20(_rewardToken);

        bool res = rewardToken.transferFrom(owner(), msg.sender, _bonusPercent);

        if (!res) {
            return false;
        }

        receiveBonus[stakeKey][msg.sender] = true;

        emit GiveBonus(_sessionId, _stakeId, _bonusPercent, _rewardToken, msg.sender, block.timestamp);

        return true;
    }


    function _claim(bytes32 key, address stakerAddr, uint interest) internal override returns(bool) {
        uint _stakeId = keyToId[key];
        TokenStaking storage tokenStaking = tokenStakings[_stakeId];

        _safeTransfer(tokenStaking.rewardToken, stakerAddr, interest);

        return true;
    }  


    function _safeTransfer(address _token, address _to, uint _amount) internal {
        if (_token != address(0)) {
            IERC20 _rewardToken = IERC20(_token);

            uint _balance = _rewardToken.balanceOf(address(this));
            require(_amount <= _balance, "MoonscapeDefi: Do not have enough token to reward");

            uint _beforBalance = _rewardToken.balanceOf(_to);
            _rewardToken.transfer(_to, _amount);

            require(_rewardToken.balanceOf(_to) == _beforBalance + _amount, "MoonscapeDefi: Invalid transfer");
        } else {

            uint _balance = address(this).balance;
            require(_amount <= _balance, "MoonscapeDefi: Do not have enough token to reward");

            payable(_to).transfer(_amount);
        }
    }

    /// @dev Token for moondust
    function tokenBuyPack(uint _sessionId, uint _typeId, uint _amount, uint _packId, uint8 _v, bytes32 _r, bytes32 _s ) public{
        require(_amount > 0, "MoonscapeDefi: The exchange amount cannot be less than zero!");

        address _tokenAddress = changeToken[_typeId];
        require(changeAllowed[_tokenAddress], "MoonscapeDefi: This token is not allowed");

        Session storage session = sessions[_sessionId];
        require(session.active, "MoonscapeDefi: Session Inactive!");

        {
            bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
            bytes32 message         = keccak256(abi.encodePacked(_sessionId, _typeId, _amount, _packId, address(this), nonce[msg.sender], msg.sender));
            bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
            address recover         = ecrecover(hash, _v, _r, _s);

            require(recover == verifier, "MoonscapeDefi: Verification failed about getBonus");
        }

        nonce[msg.sender]++;

        IERC20 token = IERC20(_tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), _amount);

        emit TokenBuyPack(_sessionId, _typeId, _amount, _packId, msg.sender, block.timestamp);
    }

    //////////////////////////////////////////////////////////////////////////
    //
    // Only owner
    //
    //////////////////////////////////////////////////////////////////////////

    /// @dev Add token exchange type moondust
    function addTokenChangeMoondustType(address _token) public onlyOwner{
        Session storage session = sessions[sessionId];
        require(session.active, "MoonscapeDefi: Session Inactive!");
        require(!changeAllowed[_token], "MoonscapeDefi: This token is added!");

        changeAllowed[_token] = true;
        changeToken[typeId] = _token;
        typeId++;
    }

    //////////////////////////////////////////////////////////////////////////
    //
    // Helpers
    //
    //////////////////////////////////////////////////////////////////////////

    function stakeKeyOf(uint _sessionId, uint _stakeId) public virtual returns(bytes32) {
        return keccak256(abi.encodePacked(_sessionId, _stakeId));
    }


    /// @dev Moonscape Game can have one season live ot once.
    function validSessionTime(uint _startTime, uint _endTime) public view returns(bool) {
        Session memory session = sessions[sessionId];

        if (_startTime > session.endTime && _startTime >= block.timestamp && _startTime < _endTime) {
            return true;
        }

        return false;
    }


    /// @dev allow transfer native token in to the contract as reward token
    receive() external payable {
        // React to receiving ether
    }


    /// @dev encrypt token data
    /// @return encrypted data
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    )
        external
        override
        returns (bytes4)
    {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}