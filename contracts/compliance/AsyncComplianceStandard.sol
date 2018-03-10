pragma solidity ^0.4.19;

import "./ComplianceStandard.sol";

contract AsyncComplianceStandard is ComplianceStandard {
    struct ComplianceCheckStatus {
        // Block when this check status has expired.
        uint256 blockToExpire;

        // 0 indicates success, non-zero is left to the caller.
        uint8 checkResult;
    }
    mapping (address => mapping (uint256 => mapping(uint8 => ComplianceCheckStatus))) statuses;

    event RequestCheckEvent(
        address instrumentAddr,
        uint256 instrumentId,
        uint8 action
    );

    event CheckCompletedEvent(
        address instrumentAddr,
        uint256 instrumentId,
        uint8 action,
        uint256 blockToExpire,
        uint8 checkResult
    );

    function requestCheck(
        address instrumentAddr, uint256 instrumentId, uint8 action
    ) fromKernel external returns (uint8)
    {
        RequestCheckEvent(instrumentAddr, instrumentId, action);
    }

    function onCheckCompleted(
        address instrumentAddr,
        uint256 instrumentId,
        uint8 action,
        uint256 blockToExpire,
        uint8 checkResult
    ) external
    {
        require(isAuthorizedToCheck(msg.sender));
        statuses[instrumentAddr][instrumentId][action] = ComplianceCheckStatus({
            blockToExpire: blockToExpire,
            checkResult: checkResult
        });
        CheckCompletedEvent(
            instrumentAddr,
            instrumentId,
            action,
            blockToExpire,
            checkResult
        );
    }

    function check(address instrumentAddr, uint256 instrumentId, uint8 action) external returns (uint8) {
        ComplianceCheckStatus storage status = statuses[instrumentAddr][instrumentId][action];
        // Check that the status check has been performed.
        require(status.blockToExpire != 0);
        // Check that the status check has not expired. 
        require(status.blockToExpire > block.number);
        return status.checkResult;
    }

    function invalidate(address instrumentAddr, uint256 instrumentId, uint8 action) external {
        require(msg.sender == instrumentAddr);
        delete statuses[instrumentAddr][instrumentId][action];
    }

    /**
     * Cost of performing a check.
     */
    function cost(address instrumentAddr, uint256 instrumentId, uint8 action) external view returns (uint256);

    function isAuthorizedToCheck(address sender) view public returns (bool);
}