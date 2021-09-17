### Operation
#### 1. Install truffle
For the installation method, please refer to https://github.com/trufflesuite/truffle
Reference could also be made to https://truffle.tryblockchain.org/

#### 2. Local initialization engineering
Create a local directory to execute:
truffle init
npm init
Install openzeppelin, the project is contract framework
npm install @openzeppelin/contracts
Install hdwallet-provider, the project is a fixed seed, the account would be the same each time
npm install @truffle/hdwallet-provider

#### 3. Write a contract

#### 4. Compile a contract
truffle compile

#### 5. Modify truffle-config.js, config network use local Ganache

#### 6. Deploy contract
truffle migrate
If it is necessary to delete build directory to recompile or execute the following order after modifying the code
truffle migrate --reset
If it is necessary to release to other environment, assign the configuration of the networks parameter in truffle-config.js
truffle migrate --network

#### 7. Enter control console Ganache to start debugging. The control console can write nodejs code and invoke web3js directly
truffle console


Debugging method=======================================================
-- Inquire account list
web3.eth.getAccounts()
-- Initialize local contract
let factory = await NFTShardedFactory.deployed();
-- or initialize contract through address
let factory = await NFTShardedFactory.at('contract address');

-- Fragmentation
factory.sharded('NFT','NFT','http://test.NFT.com','0','ERC','ERC','1000000000000000000000000000','18');
--Inquire the latest event
factory.getPastEvents('NFTSharded',{})
Parameter:
filter – Object: optional, filter events according to index parameters, e.g., {filter: {myNumber: [12,13]}} refers to all events with “myNumber”  being 12 or 13
fromBlock – Number: optional, only read the historical events in blocks starting from the number
toBlock - Number: optional, only read the historical events in blocks ending at the number, the default value is "latest"

### Debug contract
debug txid

