// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28 <0.9.0;

import {BaoFactoryBytecode} from "./BaoFactoryBytecode.sol";
import {EfficientHashLib} from "@solady/utils/EfficientHashLib.sol";

/// @title BaoFactoryDeployLib
/// @notice Deployment logic for BaoFactory via Nick's Factory
/// @dev Pure CREATE2 deployment - no vm cheats required
library BaoFactoryDeployLib {
    error NicksFactoryNotAvailable();
    error BaoFactoryDeploymentFailed();
    error BaoFactoryProxyDeploymentFailed();

    /// @notice Deploy BaoFactory via Nick's Factory
    /// @dev Nick's Factory must already exist at NICKS_FACTORY address.
    ///      This is a pure CREATE2 deployment - no vm cheats required.
    ///      Idempotent: returns existing proxy if already deployed.
    /// @return proxy The BaoFactory proxy address
    function deploy() internal returns (address proxy) {
        address nicksFactory = BaoFactoryBytecode.NICKS_FACTORY;
        
        // Nick's Factory must exist
        if (nicksFactory.code.length == 0) {
            revert NicksFactoryNotAvailable();
        }

        proxy = BaoFactoryBytecode.PREDICTED_PROXY;

        // Already deployed - return early
        if (proxy.code.length > 0) {
            return proxy;
        }

        // Deploy via Nick's Factory
        bytes32 salt = EfficientHashLib.hash(bytes(BaoFactoryBytecode.SALT));
        bytes memory creationCode = BaoFactoryBytecode.CREATION_CODE;

        /// @solidity memory-safe-assembly
        assembly {
            let codeLength := mload(creationCode)
            mstore(creationCode, salt)
            if iszero(call(gas(), nicksFactory, 0, creationCode, add(codeLength, 0x20), 0x00, 0x20)) {
                // Store error selector and revert
                mstore(0x00, 0x8a2f7a00) // BaoFactoryDeploymentFailed()
                revert(0x1c, 0x04)
            }
            mstore(creationCode, codeLength)
        }

        // Verify deployment succeeded
        if (BaoFactoryBytecode.PREDICTED_IMPLEMENTATION.code.length == 0) {
            revert BaoFactoryDeploymentFailed();
        }
        if (proxy.code.length == 0) {
            revert BaoFactoryProxyDeploymentFailed();
        }
    }
}
