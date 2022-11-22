// SPDX-License-Identifier: MIT
// https://eprint.iacr.org/2015/366.pdf

pragma solidity ^0.8.11;

library SlothVDF {

    /// @dev pow(base, exponent, modulus)
    /// @param base base
    /// @param exponent exponent
    /// @param modulus modulus
    function bexmod(
        uint256 base,
        uint256 exponent,
        uint256 modulus
    ) internal pure returns (uint256) {
        uint256 _result = 1;
        uint256 _base = base;
        for (; exponent > 0; exponent >>= 1) {
            if (exponent & 1 == 1) {
                _result = mulmod(_result, _base, modulus);
            }

            _base = mulmod(_base, _base, modulus);
        }
        return _result;
    }

    /// @dev compute sloth starting from seed, over prime, for iterations
    /// @param _seed seed
    /// @param _prime prime
    /// @param _iterations number of iterations
    /// @return sloth result
    function compute(
        uint256 _seed,
        uint256 _prime,
        uint256 _iterations
    ) internal pure returns (uint256) {
        uint256 _exponent = (_prime + 1) >> 2;
        _seed %= _prime;
        for (uint256 i; i < _iterations; ++i) {
            _seed = bexmod(_seed, _exponent, _prime);
        }
        return _seed;
    }

    /// @dev verify sloth result proof, starting from seed, over prime, for iterations
    /// @param _proof result
    /// @param _seed seed
    /// @param _prime prime
    /// @param _iterations number of iterations
    /// @return true if y is a quadratic residue modulo p
    function verify(
        uint256 _proof,
        uint256 _seed,
        uint256 _prime,
        uint256 _iterations
    ) internal pure returns (bool) {
        unchecked {
            for (uint256 i; i < _iterations; ++i) {
                _proof = mulmod(_proof, _proof, _prime);
            }
            _seed %= _prime;
            if (_seed == _proof) return true;
            if (_prime - _seed == _proof) return true;
        }
        return false;
    }
}
