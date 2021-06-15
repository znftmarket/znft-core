// SPDX-License-Identifier: ISC

pragma solidity ^0.8.4;

import "./interfaces/IProcessPayments.sol";
import "./interfaces/IAggregatorV3.sol";
import "../token/interfaces/IBEP20.sol";
import "../utils/Context.sol";
import "../utils/Ownable.sol";

contract ProcessPayments is IProcessPayments, Ownable {
    /**
     * Mapping of bytes string representing token ticker to an oracle address.
     */
    mapping(bytes => address) private _oracles;

    /**
     * Mapping of bytes string representing token ticker to token smart contract.
     */
    mapping(bytes => address) private _contracts;

    /**
     *
     */
    mapping(bytes => uint8) private _isStable;

    /**
     * @dev verifies whether a contract address is configured for a specific ticker.
     */
    modifier Available(string memory _ticker) {
        require(
            _contracts[bytes(_ticker)] != address(0),
            "PoS Error: contract address for ticker not available"
        );
        _;
    }

    /**
     * @dev validates whether the given asset is a stablecoin.
     */
    modifier Stablecoin(string memory _ticker) {
        require(
            _isStable[bytes(_ticker)] == 1,
            "PoS Error: token doesn't represent a stablecoin"
        );
        _;
    }

    /**
     * @dev sets the owners in the Ownable Contract.
     */
    constructor() Ownable() {}

    /**
     * @dev sets the address of the oracle for the token ticker.
     *
     * Requirements:
     * `_oracleAddress` is the chainlink oracle address for price.
     * `_ticker` is the TICKER for the asset. Eg., BTC for Bitcoin.
     */
    function setOracle(address _oracleAddress, string memory _ticker)
        public
        virtual
        override
        onlyOwner
        returns (bool)
    {
        require(
            _oracleAddress != address(0),
            "PoS Error: oracle cannot be a zero address"
        );
        bytes memory ticker = bytes(_ticker);

        if (_oracles[ticker] == address(0)) {
            _oracles[ticker] = _oracleAddress;
            return true;
        } else {
            revert("PoS Error: oracle address already found");
        }
    }

    /**
     * @dev sets the address of the contract for token ticker.
     *
     * Requirements:
     * `_ticker` is the TICKER of the asset.
     * `_contractAddress` is the address of the token smart contract.
     * `_contractAddress` should follow BEP20/ERC20 standards.
     *
     * @return bool representing the status of the transaction.
     */
    function setContract(address _contractAddress, string memory _ticker)
        public
        virtual
        override
        onlyOwner
        returns (bool)
    {
        require(
            _contractAddress != address(0),
            "PoS Error: contract cannot be a zero address"
        );
        bytes memory ticker = bytes(_ticker);

        if (_contracts[ticker] == address(0)) {
            _contracts[ticker] = _contractAddress;
            return true;
        } else {
            revert("PoS Error: contract already initialized.");
        }
    }

    /**
     * @dev replace the oracle for an existing ticker.
     *
     * Requirements:
     * `_newOracle` is the chainlink oracle source that's changed.
     * `_ticker` is the TICKER of the asset.
     */
    function replaceOracle(address _newOracle, string memory _ticker)
        public
        virtual
        override
        onlyOwner
        returns (bool)
    {
        require(
            _newOracle != address(0),
            "PoS Error: oracle cannot be a zero address"
        );
        bytes memory ticker = bytes(_ticker);

        if (_oracles[ticker] != address(0)) {
            _oracles[ticker] = _newOracle;
            return true;
        } else {
            revert("PoS Error: set oracle to replace.");
        }
    }

    /**
     * @dev sets the address of the contract for token ticker.
     *
     * Requirements:
     * `_ticker` is the TICKER of the asset.
     * `_contractAddress` is the address of the token smart contract.
     * `_contractAddress` should follow BEP20/ERC20 standards.
     *
     * @return bool representing the status of the transaction.
     */
    function replaceContract(address _newAddress, string memory _ticker)
        public
        virtual
        override
        onlyOwner
        returns (bool)
    {
        require(
            _newAddress != address(0),
            "PoS Error: contract cannot be a zero address"
        );
        bytes memory ticker = bytes(_ticker);

        if (_contracts[ticker] != address(0)) {
            _contracts[ticker] = _newAddress;
            return true;
        } else {
            revert("PoS Error: contract not initialized yet.");
        }
    }

    /**
     * @dev marks a specific asset as stablecoin.
     *
     * Requirements:
     * `_ticker` - TICKER of the token that's contract address is already configured.
     *
     * @return bool representing the status of the transaction.
     */
    function markAsStablecoin(string memory _ticker)
        public
        virtual
        override
        Available(_ticker)
        onlyOwner
        returns (bool)
    {
        _isStable[bytes(_ticker)] = 1;
        return true;
    }

    /**
     * @dev process payments for stablecoins.
     *
     * Requirements:
     * `_ticker` is the name of the token to be processed.
     * `_usd` is the amount of USD to be processed in 8-decimals.
     *
     * 1 Stablecoin is considered as 1 USD.
     */
    function sPayment(string memory _ticker, uint256 _usd)
        internal
        virtual
        Available(_ticker)
        Stablecoin(_ticker)
        returns (bool, uint256)
    {
        address spender = _msgSender();
        require(
            fetchApproval(_ticker, spender) >= _usd,
            "PoS Error: insufficient allowance for spender"
        );
        address contractAddress = _contracts[bytes(_ticker)];
        uint256 decimals = IBEP20(contractAddress).decimals();

        uint256 tokens;
        if (decimals > 8) {
            tokens = _usd * 10**(decimals - 8);
        } else {
            tokens = _usd * 10**(8 - decimals);
        }
        return (
            IBEP20(contractAddress).transferFrom(
                spender,
                address(this),
                tokens
            ),
            tokens
        );
    }

    /**
     * @dev process payments for tokens.
     *
     * Requirements:
     * `_ticker` of the token.
     * `_usd` is the amount of USD to be processed.
     *
     * Price of token is fetched from Chainlink.
     */
    function tPayment(string memory _ticker, uint256 _usd)
        internal
        virtual
        Available(_ticker)
        returns (bool, uint256)
    {
        uint256 amount = resolveAmount(_ticker, _usd);
        address user = _msgSender();

        require(
            fetchApproval(_ticker, user) >= amount,
            "PoS Error: Insufficient Approval"
        );
        address contractAddress = _contracts[bytes(_ticker)];
        return (
            IBEP20(contractAddress).transferFrom(user, address(this), amount),
            amount
        );
    }

    /**
     * @dev used for settle a tokens from the contract
     * to a user.
     *
     * Requirements:
     * `_ticker` of the token.
     * `_value` is the amount of tokens (decimals not handled)
     * `_to` is the address of the user.
     *
     * @return bool representing the status of the transaction.
     */
    function settle(
        string memory _ticker,
        uint256 _value,
        address _to
    ) internal virtual Available(_ticker) returns (bool) {
        address contractAddress = _contracts[bytes(_ticker)];
        return IBEP20(contractAddress).transfer(_to, _value);
    }

    /**
     * @dev checks the approval value of each token.
     *
     * Requirements:
     * `_ticker` is the name of the token to check approval.
     * '_holder` is the address of the account to be processed.
     *
     * @return the approval of any stablecoin in 18-decimal.
     */
    function fetchApproval(string memory _ticker, address _holder)
        private
        view
        returns (uint256)
    {
        address contractAddress = _contracts[bytes(_ticker)];
        return IBEP20(contractAddress).allowance(_holder, address(this));
    }

    /**
     * @dev resolves the amount of tokens to be paid for the amount of usd.
     *
     * Requirements:
     * `_ticker` represents the token to be accepted for payments.
     * `_usd` represents the value in USD.
     */
    function resolveAmount(string memory _ticker, uint256 _usd)
        private
        view
        returns (uint256)
    {
        uint256 value = _usd * 10**18;
        uint256 price = fetchOraclePrice(_ticker);

        address contractAddress = _contracts[bytes(_ticker)];
        uint256 decimal = IBEP20(contractAddress).decimals();

        require(decimal <= 18, "PoS Error: asset class cannot be supported");
        uint256 decimalCorrection = 18 - decimal;

        uint256 tokensAmount = value / price;
        return tokensAmount / 10**decimalCorrection;
    }

    /**
     * @dev returns the contract address.
     */
    function fetchContract(string memory _ticker)
        private
        view
        returns (address)
    {
        return _contracts[bytes(_ticker)];
    }

    /**
     * @dev returns the latest round price from chainlink oracle.
     *
     * Requirements:
     * `_oracleAddress` the address of the oracle.
     *
     * @return the current latest price from the oracle.
     */
    function fetchOraclePrice(string memory _ticker)
        private
        view
        returns (uint256)
    {
        address oracleAddress = _oracles[bytes(_ticker)];
        (, int256 price, , , ) = IAggregatorV3(oracleAddress).latestRoundData();
        return uint256(price);
    }
}
