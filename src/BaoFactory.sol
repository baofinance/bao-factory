// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LibClone} from "@solady/utils/LibClone.sol";
import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";

/// @title BaoFactory bootstrap
/// @author Bao Finance
/// @notice UUPS-upgradeable deterministic factory stub
/// @dev Deployed via Nick's Factory for cross-chain address consistency.
///      Owner is a compile-time constant - not transferable other than by upgrade
///
/// Architecture:
/// - Owner: Hardcoded
///
/// Security model:
/// - Owner controls upgrades
///
/// Deployment:
/// 1. Deploy this implementation via Nick's Factory (0x4e59b44847b379578588920cA78FbF26c0B4956C)
///    with a chosen salt to get a deterministic implementation address
/// 2. The constructor automatically deploys an ERC1967Proxy pointing to itself
/// 3. The proxy address is deterministic: keccak256(rlp([implementation_address, 1]))[12:]
///    This works because the implementation's address is deterministic (Nick's Factory)
///    and the nonce for the first CREATE is always 1
/// 4. Upgrade the factory with one that does something useful
///
/// To compute the proxy address off-chain:
///   implementation = predictNicksFactoryAddress(salt, initCodeHash)
///   proxy = address(uint160(uint256(keccak256(abi.encodePacked(
///       bytes1(0xd6), bytes1(0x94), implementation, bytes1(0x01)
///   )))))
///
contract BaoFactory is UUPSUpgradeable {
    /*//////////////////////////////////////////////////////////////////////////
                                    ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Caller is not owner or a valid (non-expired) operator
    error Unauthorized();

    /// @notice attempt upgrade to a zero address
    error InvalidAddress();

    /// @notice Emitted when the BaoFactory proxy is deployed
    /// @param proxy The proxy address that should be used for all interactions
    /// @param implementation The implementation address (this contract)
    event BaoFactoryDeployed(address indexed proxy, address indexed implementation);

    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    address private constant _OWNER = 0x9bABfC1A1952a6ed2caC1922BFfE80c0506364a2;

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
                                  UUPS UPGRADE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Restrict upgrades to the embedded owner
    /// @param newImplementation The new implementation address proposed for activation
    function _authorizeUpgrade(address newImplementation) internal view override {
        // Access control only; implementation target is validated by upgrade tooling
        if (msg.sender != _OWNER) {
            revert Unauthorized();
        }
        if (newImplementation == address(0)) {
            revert InvalidAddress();
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  OWNERSHIP
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the owner address (hardcoded constant)
    /// @dev compatible with https://eips.ethereum.org/EIPS/eip-173
    /// @return the owner of the contract, the address that is allowed to upgrade
    function owner() external pure returns (address) {
        return _OWNER;
    }
}
