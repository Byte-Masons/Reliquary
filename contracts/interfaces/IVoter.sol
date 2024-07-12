// SPDX-License-Identifier: MIT
pragma solidity =0.7.6 || ^0.8.13;
pragma abicoder v2;

interface IVoter {
    function claimRewards(
        address[] memory _gauges,
        address[][] memory _tokens
    ) external;

    function _ve() external view returns (address);

    function governor() external view returns (address);

    function emergencyCouncil() external view returns (address);

    function attachTokenToGauge(uint256 _tokenId, address account) external;

    function detachTokenFromGauge(uint256 _tokenId, address account) external;

    function emitDeposit(
        uint256 _tokenId,
        address account,
        uint256 amount
    ) external;

    function emitWithdraw(
        uint256 _tokenId,
        address account,
        uint256 amount
    ) external;

    function isWhitelisted(address token) external view returns (bool);

    function notifyRewardAmount(uint256 amount) external;

    function distribute(address _gauge) external;

    function gauges(address pool) external view returns (address gauge);

    function feeDistributers(
        address gauge
    ) external view returns (address feeDistributor);

    function gaugefactory() external view returns (address);

    function feeDistributorFactory() external view returns (address);

    function minter() external view returns (address);

    function factory() external view returns (address);

    function length() external view returns (uint256);

    function pools(uint256) external view returns (address);

    function isAlive(address) external view returns (bool);

    function stale(uint256 tokenId) external view returns (bool);

    function partnerNFT(uint256 tokenId) external view returns (bool);

    function setXRamRatio(uint256 _xRamRatio) external;

    function setGaugeXRamRatio(
        address[] calldata _gauges,
        uint256[] calldata _xRamRatios
    ) external;

    function resetGaugeXRamRatio(address[] calldata _gauges) external;

    function whitelist(address _token) external;

    function forbid(address _token, bool _status) external;

    function killGauge(address _gauge) external;

    function reviveGauge(address _gauge) external;

    function whitelistOperator() external view returns (address);

    function gaugeXRamRatio(address gauge) external view returns (uint256);

    function clawBackUnusedEmissions(address[] calldata _gauges) external;

    function resetVotes(uint256[] calldata tokenIds) external;

    function syncLegacyGaugeRewards(address[] calldata _gauges) external;

    function whitelistGaugeRewards(
        address[] calldata _gauges,
        address[] calldata _rewards
    ) external;

    function removeGaugeRewards(
        address[] calldata _gauges,
        address[] calldata _rewards
    ) external;

    function base() external view returns (address ram);

    function xRamAddress() external view returns (address _xRamAddress);

    function addClGaugeReward(address gauge, address reward) external;

    function removeClGaugeReward(address gauge, address reward) external;

    function designateStale(uint256 _tokenId, bool _status) external;

    function customGaugeForPool(
        address pool
    ) external view returns (address customGauge);

    function designatePartnerNFT(uint256 _tokenId, bool _status) external;

    function isGauge(address gauge) external view returns (bool _isGauge);

    function detachPartner(uint256 _tokenId) external;
}