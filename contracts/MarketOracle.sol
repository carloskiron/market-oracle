pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "./lib/Select.sol";


interface IOracle {
    function getData() external returns (uint256, bool);
}


/**
 * @title Median Oracle
 *
 * @dev Provides a value onchain that's aggregated from a whitelisted set of
        providers.
 */
contract MedianOracle is Ownable, IOracle {
    using SafeMath for uint256;

    struct Report {
        uint256 timestamp;
        uint256 payload;
    }

    // Addresses of providers authorized to push reports.
    address[] public providers;

    // Reports indexed by provider address. Report.timestamp > 0 indicates entry
    // existence.
    mapping (address => Report) public providerReports;




    event ProviderAdded(address provider);
    event ProviderRemoved(address provider);
    event ReportExpired(address provider);
    event ReportTooRecent(address provider);

    // The number of seconds after which the report is deemed expired.
    uint256 public reportExpirationTimeSec = 6 hours;

    uint256 public reportSecurityDelaySec = 1 hours;

    uint256 public minimumProviders = 1;

    function setReportExpirationTimeSec(uint256 reportExpirationTimeSec_)
    external
    onlyOwner
    {
        reportExpirationTimeSec = reportExpirationTimeSec_;
    }

    function setReportSecurityDelaySec(uint256 reportSecurityDelaySec_)
    external
    onlyOwner
    {
        reportSecurityDelaySec = reportSecurityDelaySec_;
    }

    function setMinimumProviders(uint256 minimumProviders_)
    external
    onlyOwner
    {
        require(minimumProviders_ > 0);
        minimumProviders = minimumProviders_;
    }

    function pushReport(uint256 payload) external
    {
        address sender = msg.sender;
        require(providerReports[sender].timestamp > 0);
        providerReports[sender].timestamp = now;
        providerReports[sender].payload = payload;
    }

    function getData()
        external
        returns (uint256, bool)
    {
        uint256 reportsCount = providers.length;
        uint256[] memory validReports = new uint256[](reportsCount);
        uint256 size = 0;
        uint256 minValidTimestamp =  now.sub(reportExpirationTimeSec);
        uint256 maxValidTimestamp =  now.sub(reportSecurityDelaySec);

        for (uint256 i = 0; i < reportsCount; i++) {
            address providerAddress = providers[i];
            uint256 reportTimestamp = providerReports[providerAddress].timestamp;
            if (reportTimestamp < minValidTimestamp) {
                emit ReportExpired(providerAddress);
            } else if (reportTimestamp > maxValidTimestamp) {
                emit ReportTooRecent(providerAddress);
            } else {
                validReports[size++] = providerReports[providerAddress].payload;
            }
        }

        if (size < minimumProviders) {
            return (0, false);
        }

        return (Select.computeMedian(validReports, size), true);
    }

    /**
     * @dev Authorizes a provider.
     * @param provider Address of the provider.
     */
    function addProvider(address provider)
        external
        onlyOwner
    {
        require(providerReports[provider].timestamp == 0);
        providers.push(provider);
        providerReports[provider].timestamp = 1;
        emit ProviderAdded(provider);
    }

    /**
     * @dev Revokes provider authorization.
     * @param provider Address of the provider.
     */
    function removeProvider(address provider)
        public
        onlyOwner
    {
        delete providerReports[provider];
        for (uint256 i = 0; i < providers.length; i++) {
            if (providers[i] == provider) {
                if (i + 1  != providers.length) {
                    providers[i] = providers[providers.length-1];
                }
                providers.length--;
                emit ProviderRemoved(provider);
                break;
            }
        }
    }

    /**
     * @return The number of providers.
     */
    function providersSize()
        public
        view
        returns (uint256)
    {
        return providers.length;
    }
}
