let Riverboat = artifacts.require("Riverboat");
let RiverboatNft = artifacts.require("RiverboatNft");
let RiverboaFactory = artifacts.require("RiverboaFactory");


// global variables
let accounts;
let multiplier = 1000000000000000000;

module.exports = async function(callback) {
    const networkId = await web3.eth.net.getId();
    let res = await init(networkId);
    callback(null, res);
};

let init = async function(networkId) {

    //--------------------------------------------------
    // Accounts and contracts configuration
    //--------------------------------------------------

    accounts = await web3.eth.getAccounts();
    console.log(accounts);

    let riverboat = await Riverboat.at("0x8E61f5028eEA48fdd58FD3809fc2202ABdBDC126");
    let riverboatNft     = await RiverboatNft.at("0x7115ABcCa5f0702E177f172C1c14b3F686d6A63a");
    let riverboaFactory = await RiverboaFactory.at("0x8BDc19BAb95253B5B30D16B9a28E70bAf9e0101A");


    let owner = accounts[0];
    console.log(`Using account ${owner}`);

    //--------------------------------------------------
    // Parameters setup and function calls
    //--------------------------------------------------

    let riverboatNftAddress = riverboatNft.address;
    let nftMetadataAddress = riverboaFactory.address;

    let currencyAddress = 



    // contract calls
    await startSession();

    //--------------------------------------------------
    // Functions operating the contract
    //--------------------------------------------------

    // add currency address -only needs to run once per currency
    async function startSession(){
        console.log("attempting to start session...");
        await riverboat.startSession(currencyAddress, nftAddress, lighthouseTierAddress, startPrice,
          priceIncrease, startTime, intervalDuration, intervalsAmount, slotsAmount {from: owner})
          .catch(console.error);

        let sessionId = parseInt(await riverboat.lastSessionId.call());
        console.log(`started session with id${sessionId}`);
    }

}.bind(this);
