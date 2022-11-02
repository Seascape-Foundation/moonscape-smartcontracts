var StakeNftForChain = artifacts.require("./StakeNftForChain.sol");

module.exports = async function(deployer, network) {
    let accounts = await web3.eth.getAccounts();
    console.log(`'${accounts[0]}' is the deployer!`);

    let scapeNftAddress;
    
    console.log(network,"===============");
    if (network == "bsctestnet") {
        scapeNftAddress = "0x66638F4970C2ae63773946906922c07a583b6069";
    }else if (network == "goerli-fork" || network == "goerli" ) {
        scapeNftAddress = "0xcCfBB93A8703142Ccb0c157d7Be26f7a25DfadC6";
    }

    await deployer.deploy(StakeNftForChain, scapeNftAddress);

    console.log(`Moonscape StakeNftForChain was deployed on ${StakeNftForChain.address}`);

};
