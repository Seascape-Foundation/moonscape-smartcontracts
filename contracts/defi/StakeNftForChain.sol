// SPDX-License-Identifier: MIT
pragma solidity 0.6.7;


import "./../openzeppelin/contracts/access/Ownable.sol";
import "./../openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./../openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract StakeNftForChain is Ownable, IERC721Receiver {

    uint public sessionId;
    IERC721 public nft;
    address public verifier;

 // The Staking is Time based.
    struct Session {
        uint startTime;
        uint endTime;
    }

    mapping(uint => Session) public sessions;
    mapping(address => uint) public nonce;

    event StartSession(uint indexed sessionId, uint startTime, uint endTime);
    event BurnScapeForBuilding(address indexed staker, uint indexed sessionId, uint stakeId, uint cityId, uint buildingId, uint indexed scapeNftId, uint time, uint chainId);

    constructor (address _nft) public {
    	require(_nft != address(0), "StakeNft: Nft can't be zero address");
        nft = IERC721(_nft);
    }

/// @dev start a new session
    function startSession(uint _startTime, uint _endTime, address _verifier) external onlyOwner{
        require(!isActive(_startTime, _endTime), "INVALID_SESSION_TIME");

        sessionId++;

        sessions[sessionId] = Session(_startTime, _endTime);
        verifier            = _verifier;

        emit StartSession(sessionId, _startTime, _endTime);
    }


/// @dev stake nft
    function burnScapeForBuilding(uint _sessionId, uint _stakeId, uint _cityId, uint _buildingId, uint _scapeNftId, uint _power, uint8 _v, bytes32[2] calldata sig) external {
        require(isActive(_sessionId), "session not active");

        {
            bytes memory prefix     = "\x19Ethereum Signed Message:\n32";
            bytes32 message         = keccak256(abi.encodePacked(_sessionId, _stakeId, _cityId, _buildingId, _scapeNftId, _power, nonce[msg.sender], msg.sender));
            bytes32 hash            = keccak256(abi.encodePacked(prefix, message));
            address recover         = ecrecover(hash, _v, sig[0], sig[1]);

            require(recover == verifier, "Verification failed about stakeNft");
        }

        uint chainId;   
        assembly {
            chainId := chainid()
        }

        require(nft.ownerOf(_scapeNftId) == msg.sender, "not owner");

        nonce[msg.sender]++;

        nft.safeTransferFrom(msg.sender, 0x000000000000000000000000000000000000dEaD, _scapeNftId);

        emit BurnScapeForBuilding(msg.sender, sessionId, _stakeId, _cityId, _buildingId, _scapeNftId, block.timestamp, chainId);
    }


    // function stakeKeyOf(uint _sessionId, uint _stakeId) public virtual returns(bytes32) {
    //     return keccak256(abi.encodePacked(_sessionId, _stakeId));
    // }


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

    /// @dev encrypt token data
    /// @return encrypted data
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external override returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}