// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {CREATE3} from "@solady/utils/CREATE3.sol";
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";
import {EnumerableMapLib} from "@solady/utils/EnumerableMapLib.sol";

import {IBaoFactory} from "@bao-factory/IBaoFactory.sol";

/// @title BaoFactory_v1
/// @author Bao Finance
/// @notice UUPS-upgradeable deterministic deployer using CREATE3
/// @dev Owner is a compile-time constant - not transferable other than by upgrade
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
/// - Interact with the factory through the proxy address, not the implementation.
///
contract BaoFactory_v1 is IBaoFactory, UUPSUpgradeable {
    using EnumerableMapLib for EnumerableMapLib.AddressToUint256Map;

    /*//////////////////////////////////////////////////////////////////////////
                                   STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    address private constant _OWNER = 0x9bABfC1A1952a6ed2caC1922BFfE80c0506364a2;

    /// @dev ERC-7201 namespace slot for BaoFactory storage
    // chisel eval 'keccak256(abi.encode(uint256(keccak256("bao.storage.BaoFactory")) - 1)) & ~bytes32(uint256(0xff))'
    bytes32 private constant _BAO_FACTORY_STORAGE = 0x46346a24345285b46a89a0cbc81552c1509a45bd5b640b2cdd7167d1559d8300;

    struct BaoFactoryStorage {
        /// @dev Operator address → expiry timestamp mapping with iterable access
        EnumerableMapLib.AddressToUint256Map operators;
    }

    function _storage() private pure returns (BaoFactoryStorage storage $) {
        bytes32 position = _BAO_FACTORY_STORAGE;
        assembly {
            $.slot := position
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                               OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IBaoFactory
    /// @dev Setting delay=0 removes the operator; any other value sets expiry
    function setOperator(address operator_, uint256 delay) external {
        _onlyOwner();
        BaoFactoryStorage storage $ = _storage();

        if (delay == 0) {
            $.operators.remove(operator_);
            emit OperatorRemoved(operator_);
        } else if (delay > 100 * 52 weeks) {
            revert InvalidDelay(delay);
        } else {
            uint256 expiry = block.timestamp + delay;
            $.operators.set(operator_, expiry);
            emit OperatorSet(operator_, expiry);
        }
    }

    /// @inheritdoc IBaoFactory
    function operatorAt(uint index) external view returns (address operator, uint256 expiry) {
        BaoFactoryStorage storage $ = _storage();
        (operator, expiry) = $.operators.at(index);
    }

    /// @inheritdoc IBaoFactory
    function isCurrentOperator(address addr) external view returns (bool) {
        BaoFactoryStorage storage $ = _storage();
        (bool exists, uint256 expiry) = $.operators.tryGet(addr);
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

        BaoFactoryStorage storage $ = _storage();
        (bool exists, uint256 expiry) = $.operators.tryGet(msg.sender);
        bool active = exists && expiry > block.timestamp;
        if (!active) {
            revert Unauthorized();
        }
    }
}
