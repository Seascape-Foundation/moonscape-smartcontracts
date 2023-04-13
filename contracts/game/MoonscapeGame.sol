pragma solidity 0.6.7;

import "./../openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./../openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./../openzeppelin/contracts/access/Ownable.sol";
import "./../openzeppelin/contracts/math/SafeMath.sol";
import "./../openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import "./../nfts/CityNft.sol";

contract MoonscapeGame is Ownable, IERC721Receiver {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint public sessionId;
    uint private typeId;
    uint256 private constant scaler = 10**18;

    address private cityNft;
    address private roverNft;
    address private scapeNft;
    address public feeTo;
    address public verifier;
    address private constant dead = 0x000000000000000000000000000000000000dEaD;

    // The Staking is Time based.
    struct Session {
        uint startTime;
        uint endTime;
    }

    struct Balance {
		uint256 totalSpent;      	// total amount of spend mscp
		// uint256 stakeAmount;        // current amount of staked mscp
    }

    mapping(uint => Session) public sessions;
    mapping(uint => address) public token;
    mapping(address => bool) public changeAllowed;
    /// @dev userAddress => Balance struct
    mapping(address => Balance) public balances;
    mapping(uint => address) public cityOwners;
    mapping(uint => address) public roverOwners;
    /// @dev session id => user => building => scape id
    mapping(uint => mapping(address => mapping(uint => uint))) public buildingScapeBurns;
    /// @dev session id => user => uint
    mapping(uint => mapping(address => uint)) public connectionScapeBurns;
    /// @dev userAddress => uint
    mapping(address => uint) public nonce;

    event StartSession(uint indexed sessionId, uint startTime, uint endTime);
    event AddToken(address indexed tokenAddress, uint256 indexed typeId, uint256 time);
    event Spent(address indexed spender, uint256 tokenId, uint256 amount, uint256 packageId, uint256 spentTime);
    event BurnScapeForBuilding(address indexed staker, uint sessionId, uint indexed stakeId, uint cityId, uint buildingId, uint indexed nftId, uint time, uint chainId);
    event ImportCity(address indexed staker, uint indexed id, uint time);
    event ExportCity(address indexed staker, uint indexed id, uint time);
    event MintCity(uint indexed sessionId, uint indexed cityId, uint indexed nftId, uint8 category, address staker, uint time);
    event ImportRover(address indexed staker, uint indexed id, uint time);
    event ExportRover(address indexed staker, uint indexed id, uint time);
    event MintRover(uint indexed sessionId, uint indexed id, uint8 _type, address staker, uint time);

    constructor(
        address _mscpToken,
        address _usdcToken,
        address _cityNft,
        address _roverNft,
        address _scapeNft,
        address _verifier,
        address _feeTo
    ) public {
        require(_mscpToken != address(0), "MoonscapeGame: mscpToken should not be equal to 0");
        require(_usdcToken != address(0), "MoonscapeGame: usdcToken should not be equal to 0");
        require(_cityNft   != address(0), "MoonscapeGame: cityNft should not be equal to 0");
        require(_roverNft  != address(0), "MoonscapeGame: roverNft should not be equal to 0");
        require(_scapeNft  != address(0), "MoonscapeGame: scapeNft should not be equal to 0");
        require(_verifier  != address(0), "MoonscapeGame: verifier should not be equal to 0");
        require(_feeTo     != address(0), "MoonscapeGame: feeTo should not be equal to 0");
	
        token[typeId]   = _mscpToken;
        token[++typeId] = _usdcToken;
        cityNft         = _cityNft;
        roverNft        = _roverNft;
        scapeNft        = _scapeNft;
        verifier        = _verifier;
        feeTo           = _feeTo;

        changeAllowed[_mscpToken] = true;
        changeAllowed[_usdcToken] = true;
    }

    /// @dev start a new session
    function startSession(uint _startTime, uint _endTime, address _verifier) external onlyOwner{
        require(!isActive(_startTime, _endTime), "INVALID_SESSION_TIME");

        sessionId++;

        sessions[sessionId] = Session(_startTime, _endTime);
        verifier            = _verifier;

        emit StartSession(sessionId, _startTime, _endTime);
    }

    //////////////////////////////////////////////////////////////////
    // 
    // Moonscape (MSCP) to Moondust
    // 
    //////////////////////////////////////////////////////////////////

    function purchaseMoondust(uint256 _tokenId, uint256 _amount, uint256 _packageId, uint8 _v, bytes32 _r, bytes32 _s) external {
        require(_amount > 0, "MoonscapeGame: invalid spend amount");

       
        address _tokenAddress = token[_tokenId];
        require(changeAllowed[_tokenAddress], "MoonscapeGame: This token is not allowed");

        //Verifier VRS
        {
            bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
            bytes32 message         = keccak256(abi.encodePacked(_tokenId, _amount, _packageId, address(this), nonce[msg.sender], msg.sender));
            bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
            address recover         = ecrecover(hash, _v, _r, _s);

            require(recover == verifier, "MoonscapeGame: Verification failed about spent");
        }

        IERC20 _token = IERC20(_tokenAddress);
        require(_token.balanceOf(msg.sender) >= _amount, "MoonscapeGame: not enough tokens to deposit");
        require(_token.transferFrom(msg.sender, feeTo, _amount), "MoonscapeGame: transfer of tokens to contract failed");


        nonce[msg.sender]++;

        Balance storage _balance  = balances[msg.sender];
        _balance.totalSpent = _amount.add(_balance.totalSpent);

        emit Spent(msg.sender, _tokenId, _amount, _packageId, block.timestamp);
    }

    // function stakeForMoondust(uint256 _amount) external {
    //     require(_amount > 0, "MoonscapeGame: invalid spend amount");

    //     IERC20 _token = IERC20(MSCP);
    //     require(_token.balanceOf(msg.sender) >= _amount, "MoonscapeGame: not enough tokens to deposit");
    //     require(_token.transferFrom(msg.sender, address(this), _amount), "MoonscapeGame: transfer of tokens to contract failed");

    //     Balance storage _balance  = balances[msg.sender];
    //     _balance.stakeAmount = _amount.add(_balance.stakeAmount);

    //     emit Stake(msg.sender, _amount, block.timestamp, _balance.stakeAmount);
    // }

    // function unstakeForMoondust(uint256 _amount) external {
    //     require(_amount > 0, "MoonscapeGame: invalid spend amount");

    //     Balance storage _balance  = balances[msg.sender];
    //     require(_amount <= _balance.stakeAmount, "MoonscapeGame: can't unstake more than staked");

    //     IERC20 _token = IERC20(MSCP);
    //     require(_token.balanceOf(address(this)) >= _amount, "MoonscapeGame: insufficient contract balance");

    //     require(_token.transfer(msg.sender, _amount), "MoonscapeGame: Failed to transfer token from contract to user");

    //     _balance.stakeAmount = _balance.stakeAmount.sub(_amount);

    //     emit Unstake(msg.sender, _amount, block.timestamp, _balance.stakeAmount);
    // }


    ////////////////////////////////////////
    //
    // City NFTs
    //
    ////////////////////////////////////////

    function importCity(uint _id) external {
        require(_id > 0, "MoonscapeGame: NftId can not be 0");

        CityNft nft = CityNft(cityNft);
        require(nft.ownerOf(_id) == msg.sender, "MoonscapeGame: Not city owner");

        nft.safeTransferFrom(msg.sender, address(this), _id);
        cityOwners[_id] = msg.sender;

        emit ImportCity(msg.sender, _id, block.timestamp);
    }

    function exportCity(uint _id) external {
        require(cityOwners[_id] == msg.sender, "MoonscapeGame: Not the owner");

        CityNft nft = CityNft(cityNft);
        nft.safeTransferFrom(address(this), msg.sender, _id);

        delete cityOwners[_id];

        emit ExportCity(msg.sender, _id, block.timestamp);        
    }

     function mintCity(uint _sessionId, uint _cityId, uint _nftId, uint8 _category, uint8 _v, bytes32 _r, bytes32 _s) external {
        {   // avoid stack too deep
            // investor, project verification
    	    bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
    	    bytes32 message         = keccak256(abi.encodePacked(_sessionId, _cityId, _nftId, _category, nonce[msg.sender], msg.sender));
    	    bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
    	    address recover         = ecrecover(hash, _v, _r, _s);

    	    require(recover == verifier, "MoonscapeGame: mint city NFT vrs error");
        }

        CityNft nft = CityNft(cityNft);
        require(nft.mint(_nftId, _category, msg.sender), "MoonscapeGame: Failed to mint city");

        nonce[msg.sender]++;

        emit MintCity(_sessionId, _cityId, _nftId, _category, msg.sender, block.timestamp);
    }

    /////////////////////////////////////////////////////////////////
    //
    // Burn Scape NFT for bonus in City
    //
    /////////////////////////////////////////////////////////////////

    function burnScapeForBuilding(uint _sessionId, uint _stakeId, uint _cityId, uint _buildingId, uint _scapeNftId, uint _power, uint8 _v, bytes32[2] calldata sig) external {
        // require(buildingScapeBurns[_sessionId][msg.sender][_buildingId] == 0, "MoonscapeGame: Already burnt");
        require(isActive(_sessionId), "session not active");

        {   
        // avoid stack too deep
        // investor, project verification
	    bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
	    bytes32 message         = keccak256(abi.encodePacked(_sessionId, _stakeId, _cityId, _buildingId, _scapeNftId, _power, nonce[msg.sender], msg.sender));
	    bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
	    address recover         = ecrecover(hash, _v, sig[0], sig[1]);

	    require(recover == verifier, "MoonscapeGame: sig failed about burnScapeForBuilding");
        }

        uint chainId;   
        assembly {
            chainId := chainid()
        }

        CityNft nft = CityNft(scapeNft);
        require(nft.ownerOf(_scapeNftId) == msg.sender, "MoonscapeGame: Not the owner");

        nft.safeTransferFrom(msg.sender, dead, _scapeNftId);

        buildingScapeBurns[_sessionId][msg.sender][_buildingId] = _scapeNftId;

        nonce[msg.sender]++;
        emit BurnScapeForBuilding(msg.sender, _sessionId, _stakeId, _cityId, _buildingId, _scapeNftId, block.timestamp, chainId);
    }

    // function burnScapeForConnection(uint _sessionId, uint _scapeNftId, uint8 _v, bytes32 _r, bytes32 _s) external {
    //     require(connectionScapeBurns[_sessionId][msg.sender] == 0, "Already burnt");
    //     require(_sessionId > 0, "invalid sessionId");

    //     {   // avoid stack too deep
    //     // investor, project verification
	   //  bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
	   //  bytes32 message         = keccak256(abi.encodePacked(msg.sender, _scapeNftId, _sessionId));
	   //  bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
	   //  address recover         = ecrecover(hash, _v, _r, _s);

	   //  require(recover == verifier, "MoonscapeGame: sig error");
    //     }

    //     CityNft nft = CityNft(scapeNft);
    //     nft.safeTransferFrom(msg.sender, dead, _scapeNftId);

    //     connectionScapeBurns[_sessionId][msg.sender] = _scapeNftId;

    //     emit BurnScapeForConnection(msg.sender, _scapeNftId, _sessionId);
    // }

    /////////////////////////////////////////////////////////////
    //
    // Rover
    //
    //////////////////////////////////////////////////////////////

    function importRover(uint _id) external {
        require(_id > 0, "0");

        CityNft nft = CityNft(roverNft);
        require(nft.ownerOf(_id) == msg.sender, "MoonscapeGame: Not rover owner");

        nft.safeTransferFrom(msg.sender, address(this), _id);
        roverOwners[_id] = msg.sender;

        emit ImportRover(msg.sender, _id, block.timestamp);
    }

    function exportRover(uint _id) external {
        require(roverOwners[_id] == msg.sender, "MoonscapeGame: Not the owner");

        CityNft nft = CityNft(roverNft);
        nft.safeTransferFrom(address(this), msg.sender, _id);

        delete roverOwners[_id];

        emit ExportRover(msg.sender, _id, block.timestamp);        
    }

    function mintRover(uint _sessionId, uint _nftId, uint8 _type, uint8 _v, bytes32 _r, bytes32 _s) external {
        {   // avoid stack too deep
            // investor, project verification
    	    bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
    	    bytes32 message         = keccak256(abi.encodePacked(_sessionId, _nftId, _type, nonce[msg.sender], msg.sender));
    	    bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
    	    address recover         = ecrecover(hash, _v, _r, _s);

    	    require(recover == verifier, "MoonscapeGame: mint rover NFT vrs error");
        }

        CityNft nft = CityNft(roverNft);
        require(nft.mint(_nftId, _type, msg.sender), "MoonscapeGame: Failed to mint rover");

        nonce[msg.sender]++;

        emit MintRover(_sessionId, _nftId, _type, msg.sender, block.timestamp);
    }

    function isActive(uint startTime, uint endTime) internal view returns(bool) {
        if (startTime == 0) {
            return false;
        }

        return (block.timestamp >= startTime && block.timestamp <= endTime);
    }

    /**
     * @dev session.startTime <= current time <= session.endTime
     */
    function isActive(uint _sessionId) public view returns(bool) {
        if (_sessionId == 0) return false;

        Session storage period = sessions[_sessionId];
        return (block.timestamp >= period.startTime && block.timestamp <= period.endTime);
    }

    //Add tokens that can be exchanged for gold
    function addToken(address _token) external onlyOwner {
        require(_token != address(0), "MoonscapeGame: Token can't be zero address");
        require(!changeAllowed[_token], "MoonscapeGame: This token is exist");

        changeAllowed[_token] = true;
        token[++typeId] = _token;

        emit AddToken(_token, typeId, block.timestamp);
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