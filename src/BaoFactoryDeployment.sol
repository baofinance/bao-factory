// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28 <0.9.0;

import {BaoFactory} from "./BaoFactory.sol";
import {BaoFactoryBytecode} from "./BaoFactoryBytecode.sol";
import {BaoFactoryLib} from "./BaoFactoryLib.sol";
import {LibClone} from "@solady/utils/LibClone.sol";
import {EfficientHashLib} from "@solady/utils/EfficientHashLib.sol";

/// @title BaoFactoryDeployment
/// @author Bao Finance
/// @notice Shared deployment + verification helpers for BaoFactory
/// @dev Provides the canonical "ensure" functions used by downstream projects.
library BaoFactoryDeployment {
    error NicksFactoryUnavailable();
    error BaoFactoryImplementationDeploymentFailed();
    error BaoFactoryProxyDeploymentFailed();
    error BaoFactoryProxyCodeMismatch(bytes32 expected, bytes32 actual);
    error BaoFactoryOwnerMismatch(address expected, address actual);
    error BaoFactoryProbeFailed();

    /// @notice Predict BaoFactory proxy address using captured production bytecode
    /// @return proxy The proxy address derived from the captured deployment
    function predictBaoFactoryAddress() internal pure returns (address proxy) {
        return BaoFactoryBytecode.PREDICTED_PROXY;
    }

    /// @notice Predict BaoFactory proxy address using explicit salt + code hash
    /// @param factorySalt Salt string used for CREATE2 deployment via Nick's Factory
    /// @param creationCodeHash keccak256 hash of the implementation creation code
    /// @return proxy The proxy address derived from the supplied inputs
    function predictBaoFactoryAddress(
        string memory factorySalt,
        bytes32 creationCodeHash
    ) internal pure returns (address proxy) {
        (, proxy) = BaoFactoryLib.predictAddresses(factorySalt, creationCodeHash);
    }

    /// @notice Predict BaoFactory implementation address using captured production bytecode
    /// @return implementation The implementation address derived from captured deployment
    function predictBaoFactoryImplementation() internal pure returns (address implementation) {
        return BaoFactoryBytecode.PREDICTED_IMPLEMENTATION;
    }

    /// @notice Predict BaoFactory implementation address using explicit salt + code hash
    /// @param factorySalt Salt string used for CREATE2 deployment via Nick's Factory
    /// @param creationCodeHash keccak256 hash of the implementation creation code
    /// @return implementation The implementation address derived from the supplied inputs
    function predictBaoFactoryImplementation(
        string memory factorySalt,
        bytes32 creationCodeHash
    ) internal pure returns (address implementation) {
        implementation = BaoFactoryLib.predictImplementation(factorySalt, creationCodeHash);
    }

    /// @notice Ensure BaoFactory is deployed using the captured production bytecode
    /// @return proxy The deployed BaoFactory proxy address
    function ensureBaoFactoryProduction() internal returns (address proxy) {
        proxy = ensureBaoFactoryWithConfig(
            BaoFactoryBytecode.CREATION_CODE,
            BaoFactoryBytecode.SALT,
            BaoFactoryBytecode.OWNER
        );
    }

    /// @notice Ensure BaoFactory is deployed using the current build bytecode (for tests)
    /// @return proxy The deployed BaoFactory proxy address built from the current sources
    function ensureBaoFactoryCurrentBuild() internal returns (address proxy) {
        proxy = ensureBaoFactoryWithConfig(
            type(BaoFactory).creationCode,
            BaoFactoryBytecode.SALT,
            BaoFactoryBytecode.OWNER
        );
    }

    /// @notice Deploy BaoFactory with explicit configuration (salt + creation code)
    /// @dev Reuses Nick's Factory deterministic deployment and verifies proxy invariants
    /// @param creationCode The implementation creation bytecode
    /// @param factorySalt Salt string used for Nick's Factory deployment
    /// @param expectedOwner Owner address that must be embedded in the deployed factory
    /// @return proxy The BaoFactory proxy address that satisfies the supplied invariants
    function ensureBaoFactoryWithConfig(
        bytes memory creationCode,
        string memory factorySalt,
        address expectedOwner
    ) internal returns (address proxy) {
        address nicksFactory = BaoFactoryBytecode.NICKS_FACTORY;
        if (nicksFactory.code.length == 0) {
            revert NicksFactoryUnavailable();
        }

        bytes32 creationCodeHash = EfficientHashLib.hash(creationCode);
        address implementation = BaoFactoryLib.predictImplementation(factorySalt, creationCodeHash);
        proxy = BaoFactoryLib.predictProxy(implementation);

        if (implementation.code.length == 0) {
            bytes32 salt = EfficientHashLib.hash(bytes(factorySalt));

            /// @solidity memory-safe-assembly
            // Nick's Factory deployment requires raw calldata for deterministic CREATE2 execution
            // solhint-disable-next-line no-inline-assembly
            assembly {
                let codeLength := mload(creationCode)
                mstore(creationCode, salt)
                if iszero(call(gas(), nicksFactory, 0, creationCode, add(codeLength, 0x20), 0x00, 0x20)) {
                    returndatacopy(creationCode, 0x00, returndatasize())
                    revert(creationCode, returndatasize())
                }
                mstore(creationCode, codeLength)
            }

            if (implementation.code.length == 0) {
                revert BaoFactoryImplementationDeploymentFailed();
            }
            if (proxy.code.length == 0) {
                revert BaoFactoryProxyDeploymentFailed();
            }
        }

        _verifyProxy(proxy, expectedOwner);
    }

    /// @notice Verify that the deployed proxy matches the captured runtime code and owner
    /// @param proxy The proxy address to verify
    /// @param expectedOwner The owner address that must be returned by the proxy
    function _verifyProxy(address proxy, address expectedOwner) private view {
        bytes32 expectedProxyCodeHash = LibClone.ERC1967_CODE_HASH;
        bytes32 actualProxyCodeHash;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            actualProxyCodeHash := extcodehash(proxy)
        }
        if (actualProxyCodeHash != expectedProxyCodeHash) {
            revert BaoFactoryProxyCodeMismatch(expectedProxyCodeHash, actualProxyCodeHash);
        }

        try BaoFactory(proxy).owner() returns (address currentOwner) {
            if (currentOwner != expectedOwner) {
                revert BaoFactoryOwnerMismatch(expectedOwner, currentOwner);
            }
        } catch {
            revert BaoFactoryProbeFailed();
        }
    }
}
