Deployment steps:
1. Deploy PancakeswapV2Factory.sol
2. Deploy PancakeswapV2Locker.sol
   -- Address of PancakeswapV2Factory.sol 
3. Deploy PresaleSettings.sol
4. Deploy PresaleFactory.sol
   -- Address of metamask account address & true
5. PresaleLockForwarder.sol
   -- Address of PresaleFactory.sol,
   -- Address of account from metamask,
   -- Address of PancakeswapV2Factory.sol
6. PresaleGenerator.sol
   -- Address of PresaleFactory.sol, 
   -- Address of PresaleSettings.sol
7. WBNB.sol
8. BEP20.sol
9. Presale.sol
   -- Adress of Presalegenerator metamsk,
   -- Address of PancakeswapV2Factory.sol,
   -- Address of WBNB.sol,
   -- Address of PresaleSettings.sol,
   -- Address of PresaleLockForwarder.sol,
   -- Address of presalegenerator metamask address)
