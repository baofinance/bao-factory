// SPDX-License-Identifier: MIT
pragma solidity >=0.8.28 <0.9.0;

import {UUPSUpgradeable} from "@solady/utils/UUPSUpgradeable.sol";
import {Ownable} from "@solady/auth/Ownable.sol";

/// @title FundedVault
/// @notice Simple test contract with payable constructor for testing CREATE3 value transfers
/// @dev Used to verify that ETH can be passed through CREATE3's two-step deployment
contract FundedVault {
    uint256 public initialBalance;
    address public deployer;

    /// @notice Constructor that accepts ETH
    /// @dev msg.sender will be the CREATE3 proxy, not the BaoFactory
    constructor() payable {
        initialBalance = msg.value;
        deployer = msg.sender;
    }

    /// @notice Get current ETH balance of the contract
    function currentBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

/// @title NonPayableVault
/// @notice Test contract with NON-payable constructor - rejects ETH
/// @dev Used to verify that CREATE3 value deployment fails with non-payable constructors
contract NonPayableVault {
    uint256 public value;
    address public deployer;

    /// @notice Non-payable constructor - will revert if sent ETH
    constructor(uint256 _value) {
        value = _value;
        deployer = msg.sender;
    }
}

/// @title FundedVaultUUPS
/// @notice UUPS Upgradeable vault with payable initializer
/// @dev Ownable + UUPS upgradeable contract for testing value passing through proxy deployment
contract FundedVaultUUPS is UUPSUpgradeable, Ownable {
    uint256 public initialBalance;
    address public originalDeployer;
    bool private _initialized;

    /// @dev The owner to set during initialize (stored in implementation, read by proxy)
    address private immutable _PENDING_OWNER;

    constructor(address _owner) {
        _PENDING_OWNER = _owner;
        // Don't initialize owner here - it won't carry to proxy storage
    }

    /// @notice Payable initializer - can receive ETH during initialization
    function initialize() external payable {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _initializeOwner(_PENDING_OWNER);
        initialBalance = msg.value;
        originalDeployer = msg.sender;
    }

    function currentBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

/// @title NonPayableVaultUUPS
/// @notice UUPS Upgradeable vault with NON-payable initializer
/// @dev Ownable + UUPS upgradeable contract to test that non-payable initializers reject ETH
contract NonPayableVaultUUPS is UUPSUpgradeable, Ownable {
    uint256 public value;
    address public originalDeployer;
    bool private _initialized;

    address private immutable _PENDING_OWNER;

    constructor(address _owner) {
        _PENDING_OWNER = _owner;
    }

    /// @notice NON-payable initializer - will revert if sent ETH
    function initialize(uint256 _value) external {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _initializeOwner(_PENDING_OWNER);
        value = _value;
        originalDeployer = msg.sender;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
