import { ethers } from 'hardhat';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, deployments } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const MapOfCryptoContract = await ethers.getContract('MapOfCrypto', deployer);
  console.log(MapOfCryptoContract.address);

  for (let i = 0; i < 20; i++) {
    console.log(`Creating transaction ${i}`);
    const tx = await MapOfCryptoContract.makePurchaseRequest(1, 1);
  }
};
export default func;
func.tags = ['purchases'];
