// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28 <0.9.0;

import {Vm} from "forge-std/Vm.sol";
import {BaoFactoryBytecode} from "./BaoFactoryBytecode.sol";
import {BaoFactoryDeployLib} from "./BaoFactoryDeployLib.sol";
import {IBaoFactory} from "./IBaoFactory.sol";

/// @title BaoFactoryFoundryLib
/// @notice Foundry test utilities for BaoFactory deployment (requires forge-std vm)
/// @dev Separated from BaoFactoryDeployLib to keep vm dependency isolated
library BaoFactoryFoundryLib {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @notice Ensure Nick's Factory exists (etch if missing)
    /// @dev Uses vm.etch to place Nick's Factory bytecode at the expected address
    function ensureNicksFactory() internal {
        if (BaoFactoryBytecode.NICKS_FACTORY.code.length == 0) {
            VM.etch(BaoFactoryBytecode.NICKS_FACTORY, BaoFactoryBytecode.NICKS_FACTORY_BYTECODE);
        }
    }

    /// @notice Deploy BaoFactory for testing on fresh EVM
    /// @dev Etches Nick's Factory if needed, then deploys BaoFactory.
    ///      Idempotent: returns existing proxy if already deployed.
    /// @return proxy The BaoFactory proxy address
    function deployForTesting() internal returns (address proxy) {
        ensureNicksFactory();
        return BaoFactoryDeployLib.deploy();
    }

    /// @notice Set operator on BaoFactory (pranks as owner)
    /// @dev Useful for test setup - grants operator access to test harness
    /// @param proxy The BaoFactory proxy address
    /// @param operator The operator address to authorize
    /// @param duration How long the operator authorization lasts (in seconds)
    function setOperatorForTesting(address proxy, address operator, uint256 duration) internal {
        VM.prank(BaoFactoryBytecode.OWNER);
        IBaoFactory(proxy).setOperator(operator, duration);
    }

    /// @notice Deploy BaoFactory and set caller as operator
    /// @dev Convenience function combining deployForTesting + setOperatorForTesting
    /// @param duration How long the operator authorization lasts (in seconds)
    /// @return proxy The BaoFactory proxy address
    function deployWithOperator(uint256 duration) internal returns (address proxy) {
        proxy = deployForTesting();
        setOperatorForTesting(proxy, address(this), duration);
    }
}
