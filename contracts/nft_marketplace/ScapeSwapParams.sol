pragma solidity ^0.6.7;
pragma experimental ABIEncoderV2;

import "./../openzeppelin/contracts/access/Ownable.sol";

/// @title NftSwapParams is a digital signature verifyer / nft parameters encoder / decoder
/// @author Nejc Schneider
contract ScapeSwapParams is Ownable{

    // takes in _encodedData and converts to seascape
    function isValidParams (uint256 _nftId, bytes memory _encodedData) public returns (address){

      (uint256 imgId, uint8 gen, uint8 quality, uint8 v, bytes32 r, bytes32 s) = this
          .decodeParams(_encodedData);
      bytes32 hash = this.encodeParams(imgId, gen, quality, _nftId);

      address signer = ecrecover(hash, v, r, s);
      require(signer == owner(),  "Verification failed");

    	return signer;
    }

    function encodeParams(
        uint256 _imgId,
        uint8 _gen,
        uint8 _quality,
        uint256 _nftId
    )
        public
        returns (bytes32 message)
    {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 messageNoPrefix = keccak256(abi
            .encodePacked(_imgId, _gen, _quality, _nftId));
        bytes32 hash = keccak256(abi.encodePacked(prefix, messageNoPrefix));

        return hash;
    }

    function decodeParams (bytes memory _encodedData)
        public
        returns (
            uint256 imgId,
            uint8 gen,
            uint8 quality,
            uint8 v,
            bytes32 r,
            bytes32 s
        )
    {
        (uint256 imgId, uint8 gen, uint8 quality, uint8 v, bytes32 r, bytes32 s) = abi
            .decode(_encodedData, (uint256, uint8, uint8, uint8, bytes32, bytes32));

        return (imgId, gen, quality, v, r, s);
    }
}
