// The iOS simulator and XCTest runs are development: their hangs come from
// alerts nobody answers and test hosts, and would bury real reports.
bool reportsCrashes(Map<String, String> environment) =>
    !environment.containsKey('SIMULATOR_DEVICE_NAME') &&
    !environment.containsKey('XCTestConfigurationFilePath');
