// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
import "./Ownable.sol";
import "./EnumerableSet.sol";
contract PresaleFactory is Ownable {
    address public PresaleGenerator;
    bool public allow;
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private presales;
    EnumerableSet.AddressSet private presaleGenerators;
    mapping(address => EnumerableSet.AddressSet) private presaleOwners;
    event presaleRegistered(address presaleContract);
    constructor(address _PresaleGenerator,bool _allow)public{
        PresaleGenerator = _PresaleGenerator;
        allow = _allow;
    }
    function adminAllowPresaleGenerator (address _address, bool _allow) public onlyOwner {
        if (_allow) {
            presaleGenerators.Add(_address);
        } else {
            presaleGenerators.remove(_address);
        }
    }
    function registerPresale (address _presaleAddress) public {
        require(presaleGenerators.contains(msg.sender), 'FORBIDDEN');
        presales.Add(_presaleAddress);
        emit presaleRegistered(_presaleAddress);
    }
    function presaleGeneratorsLength() external view returns (uint256) {
        return presaleGenerators.length();
    }
    function presaleGeneratorAtIndex(uint256 _index) external view returns (address) {
        return presaleGenerators.at(_index);
    }
    function presaleIsRegistered(address _presaleAddress) external view returns (bool) {
        return presales.contains(_presaleAddress);
    }
    function presalesLength() external view returns (uint256) {
        return presales.length();
    }
    function presaleAtIndex(uint256 _index) external view returns (address) {
        return presales.at(_index);
    }
    
}