pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./TokenVault.sol";
import "./ERC721Template.sol";

contract ReNFTFactory is Ownable {
    address private _erc721Template;
    address private  _tokenVault;
    address public settings;
    address public reNft;

    event NFTSharded(address indexed sender, address erc721Instance, address tokenVault);

    event Created(address indexed sender, address erc721Instance, uint256 id);

    constructor(address _settings, address _reNft){
        _erc721Template = address(new ERC721Template());
        _tokenVault = address(new TokenVault());
        settings = _settings;
        reNft = _reNft;
    }

    function setSettings(address _settings) external onlyOwner {
        settings = _settings;
    }

    function createNft(string memory nftName, string memory nftSymbol,
        string memory nftBaseUrl, uint256 id) external returns (address erc721Instance){
        // create and init erc721 contract
        erc721Instance = Clones.clone(_erc721Template);
        ERC721Template(erc721Instance).initOwner(address(this));
        ERC721Template(erc721Instance).initialize(nftName, nftSymbol, nftBaseUrl);
        // mint genesis NFT to erc20 contract
        ERC721Template(erc721Instance).mint(msg.sender, id);
        // change erc721contract owner
        ERC721Template(erc721Instance).transferOwnership(msg.sender);
        emit Created(msg.sender, erc721Instance, id);
    }

    function sharded(
        address erc721Instance,
        uint256 id,
        string memory erc20Name,
        string memory erc20Symbol,
        uint256 erc20TotalSupply,
        uint8 _feeLevel,
        uint256 poolPreTime,
        uint256 _listPrice)
    external returns (address tokenVault){
        require(erc20TotalSupply > 0, "ReNFTFactory:erc20TotalSupply must gt 0");
        // create and init erc20 contract
        tokenVault = Clones.clone(_tokenVault);
        TokenVault(tokenVault).initOwner(address(this));
        TokenVault(tokenVault).initialize(erc721Instance, msg.sender, erc20Name, erc20Symbol, 18, settings);
        TokenVault(tokenVault).initialize1(erc20TotalSupply, _feeLevel, poolPreTime, _listPrice, id, reNft);
        TokenVault(tokenVault).transferOwnership(Ownable.owner());
        ERC721Template(erc721Instance).safeTransferFrom(msg.sender, tokenVault, id);
        emit NFTSharded(msg.sender, erc721Instance, tokenVault);
    }
}
