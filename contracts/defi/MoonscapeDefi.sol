pragma solidity 0.6.7;

import "./../openzeppelin/contracts/access/Ownable.sol";
import "./../openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../openzeppelin/contracts/math/SafeMath.sol";
import "./../openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./../openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./../nfts/CityNft.sol";
import "./Stake.sol";

contract MoonscapeDefi is Stake, IERC721Receiver, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

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
    }

    /// @notice balance of lp token that each player deposited to game session
    struct Balance {               
        uint256 nftId;             // nft id
        uint256 sp;                // nft power
    }

    mapping(uint => Session) public sessions;
    mapping(bytes32 => bool) public addedStakings;
    mapping(uint => TokenStaking) public tokenStakings;         //uint stakeId => TokenStaking
    mapping(bytes32 => uint) public keyToId;                    //bytes32 key(stakeKeyOf(sessionId,stakeId)  => stakeId
    mapping(bytes32 => mapping(address => bool)) public receiveBonus; //bytes32 key(stakeKeyOf(sessionId,stakeId)=> weallet address => bool
    mapping(address => uint) public nonce;
    mapping(bytes32 => mapping(address => uint256)) public slots;
    mapping(bytes32 => mapping(address => Balance[3])) public balances;

    event StartSession(uint indexed sessionId, uint startTime, uint endTime);
    event PauseSession(uint indexed sessionId);
    event ResumeSession(uint indexed sessionId);
    // event AddStaking(uint indexed sessionId, uint indexed stakeId);
    event StakeToken(address indexed staker, uint indexed sessionId, uint stakeId, uint cityId, uint buildingId, uint indexed amount, uint nonce);
    event UnStakeToken(address indexed staker, uint indexed sessionId, uint stakeId, uint indexed amount);
    event ExportNft(address indexed staker, uint indexed sessionId, uint stakeId, uint indexed scapeNftId, uint time);
    event WithdrawAll(uint indexed sessionId, uint indexed stakeId, uint cityId, uint buildingId, uint amount, uint indexed bonusAmount, address staker, uint time);
    event GiveBonus(uint indexed sessionId,uint indexed stakeId, uint bonusAmount, address rewardToken, address indexed staker, uint time);
    event StakeNft(address indexed staker, uint indexed stakeId, uint cityId, uint buildingId, uint nft1, uint nft2, uint nft3);
    event UnStakeNft(address indexed staker, uint indexed stakeId, uint nft);
    event UnStakeAllNfts(address indexed staker, uint indexed stakeId, uint nft, uint power);

    constructor () public { }

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
    function addTokenStaking(uint _sessionId, address _stakeAddress, uint _rewardPool, address _rewardToken, bool _burn) external onlyOwner{
        bytes32 key = keccak256(abi.encodePacked(_sessionId, _stakeAddress, _rewardToken));

        require(!addedStakings[key], "MoonscapeDefi: DUPLICATE_STAKING");

        addedStakings[key] = true;

        //burn = true, the nft will burn;
        tokenStakings[++stakeId] = TokenStaking(_sessionId, _stakeAddress, _rewardPool, _rewardToken, _burn);

        bytes32 stakeKey = stakeKeyOf(sessionId, stakeId);

        keyToId[stakeKey] = stakeId;

        Session memory session = sessions[_sessionId];

        newStakePeriod(
            stakeKey,
            session.startTime,
            session.endTime,
            _rewardPool    
        );

        // emit AddStaking(_sessionId, stakeId);
    }

    /// @dev stake tokens
    function stakeToken(uint _stakeId, uint _cityId, uint _buildingId, uint _amount, uint8 _v, bytes32[2] calldata sig) external payable{
        TokenStaking storage tokenStaking = tokenStakings[_stakeId];

        // validate the session id
        bytes32 stakeKey = stakeKeyOf(tokenStaking.sessionId, _stakeId);

        require(isActive(stakeKey), "MoonscapeDefi: session not active");

        //validate stake id
        require(_stakeId <= stakeId,"MoonscapeDefi: do not have this stakeId");

        {
            bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
            bytes32 message         = keccak256(abi.encodePacked(_stakeId, tokenStaking.sessionId, _cityId, _buildingId, nonce[msg.sender], msg.sender));
            bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
            address recover         = ecrecover(hash, _v, sig[0], sig[1]);

            require(recover == verifier, "MoonscapeDefi: Verification failed about stakeToken");
        }

        nonce[msg.sender]++;

        deposit(stakeKey, msg.sender, _amount);

        if (tokenStaking.stakeToken == address(0x0)) {

            require (_amount > msg.value, "MoonscapeDefi: Not enough token to stake");

            address(this).transfer(_amount);
        } else {
            IERC20 token = IERC20(tokenStaking.stakeToken);

            require(token.balanceOf(msg.sender) >= _amount, "MoonscapeDefi: Not enough token to stake");

            token.safeTransferFrom(msg.sender, address(this), _amount);
        }

        emit StakeToken(msg.sender, tokenStaking.sessionId, _stakeId, _cityId, _buildingId, _amount, nonce[msg.sender]);
    }

    /// @dev unstake tokens
    function unStakeToken(uint _sessionId, uint _stakeId, uint _amount) public payable{
        TokenStaking storage tokenStaking = tokenStakings[_stakeId];

        bytes32 stakeKey = stakeKeyOf(_sessionId, _stakeId);

        withdraw(stakeKey, msg.sender, _amount);

        if (tokenStaking.stakeToken == address(0x0)) {

            (msg.sender).transfer(_amount);
        } else {
            IERC20 token = IERC20(tokenStaking.stakeToken);

            token.safeTransfer(msg.sender, _amount);
        }

        emit UnStakeToken(msg.sender, _sessionId, _stakeId, _amount);
    }

    /// @dev stake city or rover nfts
    function stakeNft(uint _stakeId, uint _cityId, uint _buildingId, bytes calldata data, uint8 _v, bytes32[2] calldata sig) external {
        TokenStaking storage tokenStaking = tokenStakings[_stakeId];

        bytes32 stakeKey = stakeKeyOf(tokenStaking.sessionId, _stakeId);
        require(isActive(stakeKey), "MoonscapeDefi: session not active");

        Balance[3] storage _balances = balances[stakeKey][msg.sender];
        (uint256[3] memory _nfts, uint256[3] memory _sp) = abi.decode(data, (uint256[3], uint256[3]));

        CityNft nft = CityNft(tokenStaking.stakeToken);
        // Check whether NFT is stored in the card slot
        for(uint8 _index = 0; _index < 3; ++_index){

            require(!(_balances[_index].nftId > 0 && _nfts[_index] > 0), "MoonscapeDefi: this slot is stored");

             if(_nfts[_index] > 0) {

                require(nft.ownerOf(_nfts[_index]) == msg.sender, "MoonscapeDefi: Nft is not owned by caller");
            }
        }

        //verify VRS
        {
            bytes32 _messageNoPrefix = keccak256(abi.encodePacked(_stakeId, _nfts[0], _sp[0], _nfts[1], _sp[1], _nfts[2], _sp[2], nonce[msg.sender], msg.sender));
            bytes32 _message = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageNoPrefix));
            address _recover = ecrecover(_message, _v, sig[0], sig[1]);
            require(_recover == verifier,  "Nft Staking: Seascape points verification failed");
        }

        // If deposit NFT,Transfer of NFT and change the variable 
        for (uint8 _index = 0; _index < 3; ++_index) {

            if(_nfts[_index] > 0) {
                //Deposit nft 
                nft.safeTransferFrom(msg.sender, address(this), _nfts[_index]);
                //Change solts num
                slots[stakeKey][msg.sender] = slots[stakeKey][msg.sender].add(1);
                //Update balance
                _balances[_index] = Balance(_nfts[_index], _sp[_index]);
                //Call the stake deposit and calculate the revenue
                deposit(stakeKey, msg.sender, _sp[_index]);
            }         
        }

        ++nonce[msg.sender];

        emit StakeNft(msg.sender, _stakeId, _cityId, _buildingId, _nfts[0], _nfts[1], _nfts[2]);
    }

    /// @dev unstake NFT
    function unStakeNft(uint _stakeId, uint _index) external{
        require(_index <= 2, "MoonscapeDefi: slot index is invalid");

        TokenStaking storage tokenStaking = tokenStakings[_stakeId];
        bytes32 stakeKey = stakeKeyOf(tokenStaking.sessionId, _stakeId);

        Balance storage _balance = balances[stakeKey][msg.sender][_index];

        withdraw(stakeKey, msg.sender, _balance.sp);

        CityNft nft = CityNft(tokenStaking.stakeToken);

        if(tokenStaking.burn) {
            nft.safeTransferFrom(address(this), dead, _balance.nftId);
        } else {
            nft.safeTransferFrom(address(this), msg.sender, _balance.nftId);
        }

        slots[stakeKey][msg.sender] = slots[stakeKey][msg.sender].sub(1);

        delete balances[stakeKey][msg.sender][_index];

        emit UnStakeNft(msg.sender, _stakeId, _balance.nftId);
    }

    //  /// @dev unstake NFTS
    function unStakeAllNfts(uint _stakeId) external{
        TokenStaking storage tokenStaking = tokenStakings[_stakeId];

        bytes32 stakeKey = stakeKeyOf(tokenStaking.sessionId, _stakeId);

        CityNft nft = CityNft(tokenStaking.stakeToken);

        require(slots[stakeKey][msg.sender] > 0, "MoonscapeDefi: all slots are empty");

        for (uint _index = 0; _index < 3; ++_index) {
            Balance storage _balance = balances[stakeKey][msg.sender][_index];

            if (_balance.nftId > 0){

                uint256 _nftId = _balance.nftId;
                uint256 _sp = _balance.sp;

                withdraw(stakeKey, msg.sender, _sp);
               
                if(tokenStaking.burn) {
                    nft.safeTransferFrom(address(this), dead, _nftId);
                } else {
                    nft.safeTransferFrom(address(this), msg.sender, _nftId);
                }
                
                delete balances[stakeKey][msg.sender][_index];

                emit UnStakeAllNfts(msg.sender, _stakeId, _nftId, _sp);
            }
        }

        slots[stakeKey][msg.sender] = 0;
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

    /// @dev withdraw all
    function withdrawAll(uint _stakeId, uint _cityId, uint _buildingId, uint _amount, uint _bonusAmount, uint8 _v, bytes32 _r, bytes32 _s) external {
        TokenStaking storage tokenStaking = tokenStakings[_stakeId];
        Session storage session = sessions[tokenStaking.sessionId];

        bytes32 stakeKey = stakeKeyOf(tokenStaking.sessionId, _stakeId);

        if(block.timestamp > session.endTime && _bonusAmount > 0) {
            require(verifyBonus(tokenStaking.sessionId, _stakeId, _cityId, _buildingId, _bonusAmount, _v, _r, _s));
            require(giveBonus(tokenStaking.sessionId, _stakeId, tokenStaking.rewardToken, _bonusAmount));
        }

        unStakeToken(tokenStaking.sessionId, _stakeId, _amount);

        emit WithdrawAll(tokenStaking.sessionId, _stakeId, _cityId, _buildingId, _amount, _bonusAmount, msg.sender, block.timestamp);
    }

    /// @dev verify Bonus
    function verifyBonus(uint _sessionId, uint _stakeId, uint _cityId, uint _buildingId, uint _bonusAmount, uint8 _v, bytes32 _r, bytes32 _s) internal returns(bool) {

        bytes32 stakeKey = stakeKeyOf(_sessionId, _stakeId);

        require(receiveBonus[stakeKey][msg.sender] == false, "MoonscapeDefi: already rewarded");

        {
            bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
            bytes32 message         = keccak256(abi.encodePacked(_sessionId, _stakeId, _cityId, _buildingId, _bonusAmount, nonce[msg.sender], msg.sender));
            bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
            address recover         = ecrecover(hash, _v, _r, _s);

            require(recover == verifier, "MoonscapeDefi: Verification failed about getBonus");
        }

        nonce[msg.sender]++;

        return true;
    }

    /// @dev get bonus reward after session is ended
    function giveBonus(uint _sessionId, uint _stakeId, address _rewardToken, uint _bonusAmount) internal returns(bool) {

        bytes32 stakeKey = stakeKeyOf(_sessionId, _stakeId);

        IERC20 rewardToken = IERC20(_rewardToken);

        bool res = rewardToken.transferFrom(owner(), msg.sender, _bonusAmount);

        if (!res) {
            return false;
        }

        receiveBonus[stakeKey][msg.sender] = true;

        emit GiveBonus(_sessionId, _stakeId, _bonusAmount, _rewardToken, msg.sender, block.timestamp);

        return true;
    }


    function _claim(bytes32 _key, address _stakerAddr, uint _interest) internal override returns(bool) {
        uint _stakeId = keyToId[_key];
        TokenStaking storage tokenStaking = tokenStakings[_stakeId];

        _safeTransfer(tokenStaking.rewardToken, _stakerAddr, _interest);

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