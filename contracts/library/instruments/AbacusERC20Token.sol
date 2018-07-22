pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol";
import "../../protocol/coordinator/ComplianceCoordinator.sol";

/**
 * @dev An ERC20 token that uses Abacus for compliance.
 */
contract AbacusERC20Token is StandardToken {
    ComplianceCoordinator complianceCoordinator;
    uint256 complianceProviderId;

    constructor(
        ComplianceCoordinator _complianceCoordinator,
        uint256 _complianceProviderId
    ) public
    {
        complianceCoordinator = _complianceCoordinator;
        complianceProviderId = _complianceProviderId;
    }

    function canTransfer(address to, uint256 value) public view returns (uint256, uint256) {
        return complianceCoordinator.check(complianceProviderId, this, value, msg.sender, to, 0);
    }

    function transfer(address to, uint256 value) public returns (bool) {
        uint256 checkResult;
        (checkResult,) = complianceCoordinator.hardCheck(complianceProviderId, this, value, msg.sender, to, 0);
        if (checkResult != 0) {
            return false;
        }
        return super.transfer(to, value);
    }

    function canTransferFrom(address from, address to, uint256 value) public view returns (uint256, uint256) {
        return complianceCoordinator.check(complianceProviderId, this, value, from, to, 0);
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        uint256 checkResult;
        (checkResult,) = complianceCoordinator.hardCheck(complianceProviderId, this, value, from, to, 0);
        if (checkResult != 0) {
            return false;
        }
        return super.transferFrom(from, to, value);
    }
}
