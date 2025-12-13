// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28 <0.9.0;

import {BaoFactory_v1} from "./BaoFactory_v1.sol";
import {BaoFactoryBytecode} from "./BaoFactoryBytecode.sol";
import {BaoFactoryLib} from "./BaoFactoryLib.sol";
import {IBaoFactory} from "./IBaoFactory.sol";
import {LibClone} from "@solady/utils/LibClone.sol";
import {EfficientHashLib} from "@solady/utils/EfficientHashLib.sol";
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";

/// @title BaoFactoryDeployment
/// @author Bao Finance
/// @notice Deployment mechanics and readiness checks for BaoFactory
/// @dev Provides action functions (caller must be authorized) and query functions (anyone).
///      Action functions assume correct msg.sender - authorization is caller's responsibility.
library BaoFactoryDeployment {
    /*//////////////////////////////////////////////////////////////////////////
                                    ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    error NicksFactoryUnavailable();
    error BaoFactoryNotDeployed();
    error BaoFactoryNotFunctional();
    error BaoFactoryOperatorNotSet(address operator);

    /*//////////////////////////////////////////////////////////////////////////
                                PREDICTION FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Predict BaoFactory proxy address before deployment
    /// @return proxy The deterministic proxy address
    function predictBaoFactoryAddress() internal pure returns (address proxy) {
        return BaoFactoryBytecode.PREDICTED_PROXY;
    }

    /*//////////////////////////////////////////////////////////////////////////
                            QUERY FUNCTIONS (bool)
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Check if BaoFactory bootstrap is deployed
    /// @return True if proxy exists with correct ERC1967 code
    function isBaoFactoryDeployed() internal view returns (bool) {
        address proxy = BaoFactoryBytecode.PREDICTED_PROXY;
        if (proxy.code.length == 0) return false;

        bytes32 actualCodeHash;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            actualCodeHash := extcodehash(proxy)
        }
        return actualCodeHash == LibClone.ERC1967_CODE_HASH;
    }

    /// @notice Check if BaoFactory is upgraded to v1 (functional)
    /// @dev Probes predictAddress which only exists in v1+
    /// @return True if proxy responds to v1 functions
    function isBaoFactoryFunctional() internal view returns (bool) {
        if (!isBaoFactoryDeployed()) return false;

        address proxy = BaoFactoryBytecode.PREDICTED_PROXY;
        // slither-disable-next-line low-level-calls
        (bool success, ) = proxy.staticcall(abi.encodeWithSelector(IBaoFactory.predictAddress.selector, bytes32(0)));
        return success;
    }

    /// @notice Check if an address is a current operator
    /// @param operator The address to check
    /// @return True if operator is valid and not expired
    function isOperator(address operator) internal view returns (bool) {
        if (!isBaoFactoryFunctional()) return false;

        address proxy = BaoFactoryBytecode.PREDICTED_PROXY;
        // slither-disable-next-line low-level-calls
        (bool success, bytes memory data) = proxy.staticcall(
            abi.encodeWithSelector(IBaoFactory.isCurrentOperator.selector, operator)
        );
        if (!success || data.length < 32) return false;
        return abi.decode(data, (bool));
    }

    /*//////////////////////////////////////////////////////////////////////////
                        REQUIREMENT FUNCTIONS (revert)
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Require BaoFactory bootstrap is deployed, revert otherwise
    function requireBaoFactory() internal view {
        if (!isBaoFactoryDeployed()) {
            revert BaoFactoryNotDeployed();
        }
    }

    /// @notice Require BaoFactory is upgraded to v1 (functional), revert otherwise
    function requireFunctionalBaoFactory() internal view {
        if (!isBaoFactoryFunctional()) {
            revert BaoFactoryNotFunctional();
        }
    }

    /// @notice Require an address is a current operator, revert otherwise
    /// @param operator The address to check
    function requireOperator(address operator) internal view {
        if (!isOperator(operator)) {
            revert BaoFactoryOperatorNotSet(operator);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                        ACTION FUNCTIONS (caller authorization)
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Deploy BaoFactory bootstrap via Nick's Factory
    /// @dev Permissionless - anyone can deploy. Idempotent if already deployed.
    /// @return proxy The deployed proxy address
    function deployBaoFactory() internal returns (address proxy) {
        address nicksFactory = BaoFactoryBytecode.NICKS_FACTORY;
        if (nicksFactory.code.length == 0) {
            revert NicksFactoryUnavailable();
        }

        bytes memory creationCode = BaoFactoryBytecode.CREATION_CODE;
        string memory factorySalt = BaoFactoryBytecode.SALT;

        bytes32 creationCodeHash = EfficientHashLib.hash(creationCode);
        address implementation = BaoFactoryLib.predictImplementation(factorySalt, creationCodeHash);
        proxy = BaoFactoryLib.predictProxy(implementation);

        // Already deployed - return early
        if (proxy.code.length > 0) {
            return proxy;
        }

        bytes32 salt = EfficientHashLib.hash(bytes(factorySalt));

        /// @solidity memory-safe-assembly
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
    }

    /// @notice Upgrade BaoFactory to a new implementation
    /// @dev Caller must be owner. Use upgradeBaoFactoryToV1() for convenience.
    /// @param impl The new implementation address (must already be deployed)
    function upgradeBaoFactory(address impl) internal {
        address proxy = BaoFactoryBytecode.PREDICTED_PROXY;
        UUPSUpgradeable(proxy).upgradeToAndCall(impl, "");
    }

    /// @notice Deploy BaoFactory_v1 and upgrade to it
    /// @dev Caller must be owner. Convenience wrapper around upgradeBaoFactory.
    function upgradeBaoFactoryToV1() internal {
        BaoFactory_v1 v1Impl = new BaoFactory_v1();
        upgradeBaoFactory(address(v1Impl));
    }
}
