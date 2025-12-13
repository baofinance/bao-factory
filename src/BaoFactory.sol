// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CREATE3} from "@solady/utils/CREATE3.sol";
import {LibClone} from "@solady/utils/LibClone.sol";
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";
import {EnumerableMapLib} from "@solady/utils/EnumerableMapLib.sol";

import {IBaoFactory} from "@bao-factory/IBaoFactory.sol";

/// @title BaoFactoryOwnerless
/// @author Bao Finance
/// @notice UUPS-upgradeable deterministic deployer using CREATE3
/// @dev Deployed via Nick's Factory for cross-chain address consistency.
///      Owner is a compile-time constant - not transferable other than by upgrade
///      Operators are temporary deployers with expiry timestamps.
///
/// Architecture:
/// - Owner: Hardcoded
/// - Operators: Time-limited deployers, set by owner with expiry delay
/// - Deployments: CREATE3 for address determinism independent of initCode
///
/// Security model:
/// - Owner controls upgrades and operator lifecycle
/// - Operators can only deploy, cannot modify contract state
/// - Expired operators are automatically invalidated (no cleanup needed)
///
/// Deployment:
/// 1. Deploy this implementation via Nick's Factory (0x4e59b44847b379578588920cA78FbF26c0B4956C)
///    with a chosen salt to get a deterministic implementation address
/// 2. The constructor automatically deploys an ERC1967Proxy pointing to itself
/// 3. The proxy address is deterministic: keccak256(rlp([implementation_address, 1]))[12:]
///    This works because the implementation's address is deterministic (Nick's Factory)
///    and the nonce for the first CREATE is always 1
/// 4. Interact with the factory through the proxy address, not the implementation.
///    (both have the same owner and will deploy to different addresses)
///
/// To compute the proxy address off-chain:
///   implementation = predictNicksFactoryAddress(salt, initCodeHash)
///   proxy = address(uint160(uint256(keccak256(abi.encodePacked(
///       bytes1(0xd6), bytes1(0x94), implementation, bytes1(0x01)
///   )))))
///
contract BaoFactory is IBaoFactory, UUPSUpgradeable {
    using EnumerableMapLib for EnumerableMapLib.AddressToUint256Map;

    /*//////////////////////////////////////////////////////////////////////////
                                   STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    address private constant _OWNER = 0x9bABfC1A1952a6ed2caC1922BFfE80c0506364a2;

    /// @dev Operator address → expiry timestamp mapping
    ///      Uses EnumerableMapLib for gas-efficient iteration and O(1) lookups
    EnumerableMapLib.AddressToUint256Map private _operators;

    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Deploys the ERC1967Proxy pointing to this implementation
    /// @dev The proxy address is deterministic based on this implementation's address
    ///      Proxy = keccak256(rlp([address(this), 1]))[12:]
    ///      Since nonce=1 for a fresh contract's first CREATE, this is predictable
    ///      Uses Solady's LibClone for a gas-optimized 61-byte ERC1967 proxy
    constructor() {
        address proxy = LibClone.deployERC1967(address(this));
        emit BaoFactoryDeployed(proxy, address(this));
    }

    /*//////////////////////////////////////////////////////////////////////////
                               OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaoFactory
    /// @dev Setting delay=0 removes the operator; any other value sets expiry
    function setOperator(address operator_, uint256 delay) external {
        _onlyOwner();

        if (delay == 0) {
            _operators.remove(operator_);
            emit OperatorRemoved(operator_);
        } else if (delay > 100 * 52 weeks) {
            revert InvalidDelay(delay);
        } else {
            uint256 expiry = block.timestamp + delay;
            _operators.set(operator_, expiry);
            emit OperatorSet(operator_, expiry);
        }
    }

    /// @inheritdoc IBaoFactory
    function operatorAt(uint index) external view returns (address operator, uint256 expiry) {
        (operator, expiry) = _operators.at(index);
    }

    /// @inheritdoc IBaoFactory
    function isCurrentOperator(address addr) external view returns (bool) {
        (bool exists, uint256 expiry) = _operators.tryGet(addr);
        return exists && expiry > block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  DEPLOYMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaoFactory
    /// @dev Address depends only on this factory's address and salt, not initCode
    function deploy(bytes calldata initCode, bytes32 salt) external returns (address deployed) {
        _onlyOwnerOrOperator();

        deployed = CREATE3.deployDeterministic(initCode, salt);
        emit Deployed(deployed, salt, 0);
    }

    /// @inheritdoc IBaoFactory
    /// @dev Value is forwarded to the deployed contract's constructor
    function deploy(uint256 value, bytes calldata initCode, bytes32 salt) external payable returns (address deployed) {
        _onlyOwnerOrOperator();

        if (msg.value != value) {
            revert ValueMismatch(value, msg.value);
        }
        deployed = CREATE3.deployDeterministic(value, initCode, salt);
        emit Deployed(deployed, salt, value);
    }

    /// @inheritdoc IBaoFactory
    /// @dev Address is independent of initCode (CREATE3 property)
    function predictAddress(bytes32 salt) external view returns (address predicted) {
        predicted = CREATE3.predictDeterministicAddress(salt);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  UUPS UPGRADE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Restrict upgrades to the embedded owner
    /// @param newImplementation The new implementation address proposed for activation (unused)
    function _authorizeUpgrade(address newImplementation) internal view override {
        // Access control only; implementation target is validated by upgrade tooling
        newImplementation; // silence solc unused var warning
        _onlyOwner();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   Ownership
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaoFactory
    function owner() external pure returns (address) {
        return _OWNER;
    }

    /*//////////////////////////////////////////////////////////////////////////
                             ACCESS CONTROL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Revert unless the caller is the baked-in owner
    function _onlyOwner() private view {
        if (msg.sender != _OWNER) {
            revert Unauthorized();
        }
    }

    /// @notice Ensure caller is either the owner or an operator that has not expired
    /// @dev Owner check is first since it's a cheap constant comparison
    function _onlyOwnerOrOperator() private view {
        if (msg.sender == _OWNER) {
            return;
        }

        (bool exists, uint256 expiry) = _operators.tryGet(msg.sender);
        bool active = exists && expiry > block.timestamp;
        if (!active) {
            revert Unauthorized();
        }
    }
}
