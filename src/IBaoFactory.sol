// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28 <0.9.0;

/***************************************************************
 *  THIS CODE IS UNDER DEVELOPMENT - DO NOT USE IN PRODUCTION  *
 ***************************************************************/

/// @title IBaoFactory
/// @author Bao Finance
/// @notice Interface for BaoFactory - errors, events, and external functions
/// @dev Import this interface instead of BaoFactoryOwnerless for cleaner dependencies
interface IBaoFactory {
    /*//////////////////////////////////////////////////////////////////////////
                                    ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Caller is not owner or a valid (non-expired) operator
    error Unauthorized();

    /// @notice attempt to set a delay that is out of range;
    error InvalidDelay(uint256 delay);

    /// @notice msg.value does not match the declared value parameter
    /// @param expected The value parameter passed to deploy()
    /// @param received The actual msg.value
    error ValueMismatch(uint256 expected, uint256 received);

    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an operator is added or has expiry extended
    /// @param operator The operator address
    /// @param expiry Unix timestamp when operator access expires
    event OperatorSet(address indexed operator, uint256 indexed expiry);

    /// @notice Emitted when an operator is explicitly removed
    /// @param operator The operator address that was removed
    event OperatorRemoved(address indexed operator);

    /// @notice Emitted after a successful CREATE3 deployment
    /// @param deployed The address of the newly deployed contract
    /// @param salt The salt used for deterministic address derivation
    /// @param value ETH value sent to the deployed contract's constructor
    event Deployed(address indexed deployed, bytes32 indexed salt, uint256 indexed value);

    /// @notice Emitted when the BaoFactory proxy is deployed
    /// @param proxy The proxy address that should be used for all interactions
    /// @param implementation The implementation address (this contract)
    event BaoFactoryDeployed(address indexed proxy, address indexed implementation);

    /*//////////////////////////////////////////////////////////////////////////
                                  FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Return the baked-in owner address
    /// @return ownerAddress Hardcoded controller for upgrades and operator management
    function owner() external view returns (address ownerAddress);

    /// @notice Grant, refresh, or revoke operator permissions
    /// @dev Setting delay = 0 removes the entry; any other value sets expiry to block.timestamp + delay
    /// @param operator_ Address to grant or revoke operator privileges
    /// @param delay Duration in seconds from now until expiry (0 = remove, capped at 100 * 52 weeks)
    function setOperator(address operator_, uint256 delay) external;

    /// @notice Return the operator record stored at a specific index
    /// @dev Includes expired operators until they are explicitly removed
    /// @return operator The operator address at the given index
    /// @return expiry The expiry timestamp paired with that operator
    function operatorAt(uint index) external view returns (address operator, uint256 expiry);

    /// @notice Check whether an address is currently a valid operator
    /// @param addr Address to check
    /// @return True if addr is registered and not expired
    function isCurrentOperator(address addr) external view returns (bool);

    /// @notice Deploy a contract deterministically via CREATE3 with zero ETH
    /// @param initCode Contract creation bytecode including constructor args
    /// @param salt Unique salt for deterministic address derivation
    /// @return deployed Address of the newly deployed contract
    function deploy(bytes calldata initCode, bytes32 salt) external returns (address deployed);

    /// @notice Deploy a contract deterministically via CREATE3 and forward ETH
    /// @param value ETH amount to send (must equal msg.value)
    /// @param initCode Contract creation bytecode including constructor args
    /// @param salt Unique salt for deterministic address derivation
    /// @return deployed Address of the newly deployed contract
    function deploy(uint256 value, bytes calldata initCode, bytes32 salt) external payable returns (address deployed);

    /// @notice Compute the CREATE3 deterministic address for a given salt
    /// @param salt The salt that would be used for deployment
    /// @return predicted The address where a contract would be deployed
    function predictAddress(bytes32 salt) external view returns (address predicted);
}
