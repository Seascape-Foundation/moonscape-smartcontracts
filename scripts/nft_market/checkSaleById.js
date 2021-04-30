let NftMarket = artifacts.require("NftMarket");
let Crowns = artifacts.require("CrownsToken");
let Nft = artifacts.require("SeascapeNft");


let accounts;

module.exports = async function(callback) {
    const networkId = await web3.eth.net.getId();
    let res = await init(networkId);
    callback(null, res);
};

let init = async function(networkId) {
    accounts = await web3.eth.getAccounts();
    console.log(accounts);

    let nftMarket = await NftMarket.at("0xd79a536581166551b5a4ded9eAC6822627e755bE");
    let nft     = await Nft.at("0x7115ABcCa5f0702E177f172C1c14b3F686d6A63a");
    let crowns  = await Crowns.at("0x168840Df293413A930d3D40baB6e1Cd8F406719D");


    let user = accounts[0];
    console.log(`Using ${user}`);

    //let nftId = await nft.tokenOfOwnerByIndex(user, 0).catch(e => console.error(e));
    let nftId = 5;

    //approve transfer of nft
    let forSale = await nftMarket.getSales(1, {from: user}).catch(console.error);
    console.log(forSale);

}.bind(this);
