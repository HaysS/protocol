pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../ProviderRegistry.sol";
import "../../library/compliance/ComplianceStandard.sol";

/**
 * Registry for compliance providers.
 */
contract ComplianceCoordinator {
    ProviderRegistry public providerRegistry;

    constructor(ProviderRegistry _providerRegistry) public  {
        providerRegistry = _providerRegistry;
    }

    struct CheckResult {
        /**
         * @dev Block when this check status has expired. 0 if we haven't writen.
         */
        uint256 blockToExpire;

        /**
         * @dev Result of the check. 0 indicates success, non-zero is left to the caller.
         */
        uint256 checkResult;
    }

    /**
     * @dev Mapping of action hash to the check result.
     */
    mapping(uint256 => CheckResult) checkResults;

    /**
     * @dev Emitted when a compliance check is performed.
     *
     * @param providerId The id of the provider.
     * @param providerVersion The version of the provider.
     * @param instrumentAddr The address of the instrument contract.
     * @param instrumentIdOrAmt The instrument id (NFT) or amount (ERC20).
     * @param from The from address of the token transfer.
     * @param to The to address of the token transfer.
     * @param data Any additional data related to the action.
     * @param checkResult The result of the compliance check.
     */
    event ComplianceCheckPerformed(
        uint256 indexed providerId,
        uint256 providerVersion,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data,
        uint256 checkResult
    );

    /**
     * @dev Emitted when the result of an asynchronous compliance check is written.
     *
     * @param providerId The id of the compliance check request.
     * @param blockToExpire The block in which the compliance check result expires.
     * @param checkResult The result of the compliance check.
     */
    event ComplianceCheckResultWritten(
        uint256 indexed providerId,
        uint256 actionHash,
        uint256 providerVersion,
        uint256 blockToExpire,
        uint256 checkResult
    );

    /**
     * @dev Writes the result of an asynchronous compliance check to the blockchain.
     *
     * @param blockToExpire The block in which the compliance check result expires.
     * @param checkResult The result of the compliance check.
     */
    function writeCheckResult(
        uint256 providerId,
        uint256 providerVersion,
        uint256 actionHash,
        uint256 blockToExpire,
        uint256 checkResult
    ) external
    {
        uint256 id;
        address owner;
        uint256 version;
        (id,,, owner,version,) = providerRegistry.latestProvider(providerId);

        // Check service exists
        require(id != 0);
        // Check provider version is correct
        require(version == providerVersion);
        // Check service owner is correct
        require(msg.sender == owner);

        // Overwrite existing action
        checkResults[actionHash] = CheckResult({
            blockToExpire: blockToExpire,
            checkResult: checkResult
        });

        emit ComplianceCheckResultWritten({
            providerId: providerId,
            actionHash: actionHash,
            providerVersion: providerVersion,
            blockToExpire: blockToExpire,
            checkResult: checkResult
        });
    }

    /**
     * @dev Invalidates a stored asynchronous compliance check result.
     * This can only be called by the owner of the provider or by the instrument that
     * requested the compliance check.
     */
    function invalidateCheckResult(
        uint256 providerId,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) external
    {
        uint256 actionHash = computeActionHash(
            providerId,
            providerRegistry.latestProviderVersion(providerId),
            instrumentAddr,
            instrumentIdOrAmt,
            from,
            to,
            data
        );
        address owner = providerRegistry.providerOwner(providerId);
        require(msg.sender == owner || msg.sender == instrumentAddr);
        delete checkResults[actionHash];
    }

    /**
     * @dev Computes an id for an action using keccak256.
     */
    function computeActionHash(
        uint256 providerId,
        uint256 providerVersion,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) pure public returns (uint256)
    {
        return uint256(
            keccak256(
                abi.encodePacked(
                    providerId,
                    providerVersion,
                    instrumentAddr,
                    instrumentIdOrAmt,
                    from,
                    to,
                    data
                )
            )
        );
    }

    uint256 constant public E_CASYNC_CHECK_NOT_PERFORMED = 100;
    uint256 constant public E_CASYNC_CHECK_NOT_EXPIRED = 101;

    /**
     * @dev Checks the result of an async service.
     * Assumes the service is async. Check your preconditions before calling.
     */
    function checkAsync(
        uint256 providerId,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) view private returns (uint256, uint256)
    {
        uint256 actionHash = computeActionHash(
            providerId,
            providerRegistry.latestProviderVersion(providerId),
            instrumentAddr,
            instrumentIdOrAmt,
            from,
            to,
            data
        );
        CheckResult storage result = checkResults[actionHash];

        // Check that the status check has been performed.
        if (result.blockToExpire == 0) {
            return (E_CASYNC_CHECK_NOT_PERFORMED, 0);
        }

        // Check that the status check has not expired. 
        if (result.blockToExpire < block.number) {
            return (E_CASYNC_CHECK_NOT_EXPIRED, 0);
        }

        return (result.checkResult, actionHash);
    }

    /**
     * @dev Performs a compliance check.
     */
    function check(
        uint256 providerId,
        address instrumentAddr,
        uint256 instrumentIdOrAmt,
        address from,
        address to,
        bytes32 data
    ) public returns (uint256)
    {
        address owner;
        uint256 providerVersion;
        bool isAsync;
        (,,, owner, providerVersion, isAsync) = providerRegistry.latestProvider(providerId);

        uint256 checkResult;
        if (isAsync) {
            uint256 actionHash;
            // Async checks
            (checkResult, actionHash) = checkAsync(
                providerId,
                instrumentAddr,
                instrumentIdOrAmt,
                from,
                to,
                data
            );
            // Invalidate check result if successful check.
            if (checkResult == 0) {
                delete checkResults[actionHash];
            }
        } else {
            // Sync checks -- call method on compliance standard
            checkResult = ComplianceStandard(owner).performCheck(
                instrumentAddr,
                instrumentIdOrAmt,
                from,
                to,
                data
            );
        }

        emit ComplianceCheckPerformed({
            providerId: providerId,
            providerVersion: providerVersion,
            instrumentAddr: instrumentAddr,
            instrumentIdOrAmt: instrumentIdOrAmt,
            from: from,
            to: to,
            data: data,
            checkResult: checkResult
        });
        return checkResult;
    }

}
