import '../../contracts/Reliquary.sol';

/// this contract extend Reliquary and provide some fonctions to help extract invariants
contract ReliquaryEchidna is Reliquary {
    constructor(
        address _rewardToken,
        address _emissionCurve,
        string memory name,
        string memory symbol
    ) Reliquary(_rewardToken, _emissionCurve, name, symbol) {}

    function getPoolLength() public view returns (uint, uint, uint) {
        return (
            poolToken.length,
            nftDescriptor.length,
            // levels.length, // private
            // poolInfo.length, // private
            rewarder.length
        );
    }

    function exists(uint id) public returns (bool) {
        return _exists(id);
    }
    function poolBalanceSum(uint pid) external view returns (uint total) {
        LevelInfo memory level = getLevelInfo(pid);
        uint length = level.balance.length;
        for (uint i; i < length;) {
            total += level.balance[i] * level.multipliers[i];
            unchecked {
                ++i;
            }
        }
    }

    function poolBalance(uint pid) public view returns (uint) {
        return _poolBalance(pid);
    }

    function updateAllPools() public {
        for (uint i; i < poolLength(); ) {
            _updatePool(i);
            unchecked {
                ++i;
            }
        }
    }
}
