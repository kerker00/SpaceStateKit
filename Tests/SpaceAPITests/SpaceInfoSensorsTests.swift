import Foundation
import Testing
import SpaceAPI

struct SpaceInfoSensorsTests {
    private func decode(_ sensors: String, decoder: JSONDecoder = JSONDecoder()) throws -> SpaceInfo {
        try decoder.decode(SpaceInfo.self, from: Data(
            "{\"space\":\"Sensor space\",\"state\":{\"open\":true},\"sensors\":\(sensors)}".utf8))
    }

    @Test func readsV15ClimateAndMetadata() throws {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Fixture.data("leinelab-v15"))
        let sensor = try #require(info.sensors.temperature.first)
        #expect(sensor.value == 12.17)
        #expect(sensor.unit == "°C")
        #expect(sensor.location == "Outdoor")
        #expect(sensor.name == "Outdoor Temperature")
        #expect(sensor.description == "Sensor mounted under roof")
        #expect(sensor.lastChange == Date(timeIntervalSince1970: 1_791_735_549))
        #expect(info.sensors.temperature.count == 4)
        #expect(info.sensors.humidity.map(\.value) == [53.13, 77.05, 52.52])
        #expect(info.sensors.carbonDioxide.first?.value == 538)
        #expect(info.sensors.barometer.map(\.value) == [1002.9, 1002.3])
        #expect(info.status == .open)
    }

    @Test func readsV15DoorsAndSupplies() throws {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Fixture.data("leinelab-v15"))
        #expect(info.sensors.doorLocked.map(\.value) == [true, false, false])
        #expect(info.sensors.doorLocked.first?.location == "Makerspace")
        #expect(info.sensors.beverageSupply.count == 14)
        #expect(info.sensors.beverageSupply.first?.unit == "btl")
        #expect(info.sensors.beverageSupply.contains { $0.value == 0 })
        #expect(info.sensors.totalMemberCount.first?.value == 124)
    }

    @Test func readsV14SensorsWithoutInventingDates() throws {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Fixture.data("chaosstuff-v14"))
        #expect(info.sensors.barometer.map(\.value) == [973, 973, 972, 973])
        #expect(info.sensors.humidity.first?.value == 30.33)
        #expect(info.sensors.beverageSupply.first?.value == 260)
        #expect(info.sensors.barometer.allSatisfy { $0.lastChange == nil })
        #expect(info.sensors.peopleNowPresent.map(\.value) == [0])
        #expect(info.sensors.totalMemberCount.map(\.value) == [17, 8])
        #expect(info.status == .closed)
    }

    @Test func readsMainframeNetworkCounts() throws {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Fixture.data("mainframe-spaceinfo"))
        #expect(info.sensors.networkConnections.first?.value == 118)
        #expect(info.sensors.networkConnections.first?.name == "deviceCount")
        #expect(info.sensors.networkConnections.first?.location == "Inside")
        #expect(info.sensors.networkConnections.map(\.value) == [118, 1])
        #expect(info.sensors.peopleNowPresent.first?.value == 8)
    }

    @Test func skipsOnlyBadFixtureReadings() throws {
        let info = try JSONDecoder().decode(SpaceInfo.self, from: Fixture.data("broken-fields"))
        #expect(info.sensors.temperature == [SpaceInfo.Sensor(value: 21.5, unit: "°C", location: "Lab")])
        #expect(info.sensors.peopleNowPresent.map(\.value) == [3])
        // A lone object is not silently converted to an array.
        #expect(info.sensors.doorLocked.isEmpty)
        #expect(info.status == .open)
        #expect(info.feeds.calendar != nil)
    }

    @Test func missingOrMalformedSensorContainerLeavesSpaceReadable() throws {
        for raw in ["null", "true", "42", "\"broken\"", "[]", "{}"] {
            let info = try decode(raw)
            #expect(info.sensors == SpaceInfo.Sensors())
            #expect(info.status == .open)
        }
        let missing = try JSONDecoder().decode(SpaceInfo.self, from: Data(#"{"space":"No sensors"}"#.utf8))
        #expect(missing.sensors == SpaceInfo.Sensors())
    }

    @Test func skipsBrokenEntriesAndKeepsOrderAndOtherKinds() throws {
        let info = try decode(#"""
            {"temperature":[null,7,"bad",{},[],{"unit":"°C"},{"value":null},
                            {"value":20},{"value":"warm"},{"value":21}],
             "humidity":[{"value":60,"unit":"%"}],"barometer":"bad"}
            """#)
        #expect(info.sensors.temperature.map(\.value) == [20, 21])
        #expect(info.sensors.humidity.first?.value == 60)
        #expect(info.sensors.barometer.isEmpty)
        #expect(info.status == .open)
    }

    @Test func malformedOptionalMetadataDoesNotDiscardValue() throws {
        let info = try decode(#"""
            {"temperature":[{"value":20,"unit":[],"location":42,"name":false,
                             "description":{},"lastchange":"yesterday"}]}
            """#)
        #expect(info.sensors.temperature == [SpaceInfo.Sensor(value: 20.0)])
    }

    @Test func preservesMissingAndUnknownUnitsWithoutConversion() throws {
        let info = try decode(#"""
            {"temperature":[{"value":68,"unit":"°F"},{"value":20},{"value":300,"unit":"custom"}],
             "humidity":[{"value":101,"unit":"%"}]}
            """#)
        #expect(info.sensors.temperature.map(\.value) == [68, 20, 300])
        #expect(info.sensors.temperature.map(\.unit) == ["°F", nil, "custom"])
        // Parsing is not physical calibration or schema range enforcement.
        #expect(info.sensors.humidity.first?.value == 101)
    }

    @Test func doesNotCoerceBooleanNumbersOrStrings() throws {
        let info = try decode(#"""
            {"temperature":[{"value":true},{"value":"21"},{"value":21}],
             "door_locked":[{"value":1},{"value":"false"},{"value":false}],
             "people_now_present":[{"value":"3"},{"value":true},{"value":3}]}
            """#)
        #expect(info.sensors.temperature.map(\.value) == [21])
        #expect(info.sensors.doorLocked.map(\.value) == [false])
        #expect(info.sensors.peopleNowPresent.map(\.value) == [3])
    }

    @Test func keepsZeroFalseAndNegativeMeasurements() throws {
        let info = try decode(#"""
            {"temperature":[{"value":-10.5}],"door_locked":[{"value":false}],
             "people_now_present":[{"value":0}],"beverage_supply":[{"value":0}]}
            """#)
        #expect(info.sensors.temperature.first?.value == -10.5)
        #expect(info.sensors.doorLocked.first?.value == false)
        #expect(info.sensors.peopleNowPresent.first?.value == 0)
        #expect(info.sensors.beverageSupply.first?.value == 0)
    }

    @Test func decodesAllTypedCountsAndPowerFields() throws {
        let info = try decode(#"""
            {"people_now_present":[{"value":3}],"total_member_count":[{"value":150}],
             "network_connections":[{"value":18}],"power_consumption":[{"value":1200,"unit":"W"}],
             "power_generation":[{"value":450.5,"unit":"VA"}],"carbondioxide":[{"value":600,"unit":"ppm"}]}
            """#)
        #expect(info.sensors.peopleNowPresent.first?.value == 3)
        #expect(info.sensors.totalMemberCount.first?.value == 150)
        #expect(info.sensors.networkConnections.first?.value == 18)
        #expect(info.sensors.powerConsumption.first?.unit == "W")
        #expect(info.sensors.powerConsumption.first?.value == 1200)
        #expect(info.sensors.powerGeneration.first?.unit == "VA")
        #expect(info.sensors.powerGeneration.first?.value == 450.5)
        #expect(info.sensors.carbonDioxide.first?.unit == "ppm")
        #expect(info.sensors.other.isEmpty)
    }

    @Test func omitsVisitorNamesAndConnectedMachineLists() throws {
        let withNames = try decode(#"""
            {"people_now_present":[{"value":3,"names":["Person A","Person B"]}],
             "network_connections":[{"value":2,"machines":[{"name":"laptop","mac":"hidden"}]}]}
            """#)
        let countsOnly = try decode(#"""
            {"people_now_present":[{"value":3}],"network_connections":[{"value":2}]}
            """#)
        #expect(withNames == countsOnly)
        #expect(withNames.sensors.other.isEmpty)
    }

    @Test func retainsUnknownKindsAndCompoundData() throws {
        let info = try decode(#"""
            {"radiation":{"alpha":[{"value":0.1,"unit":"µSv/h","conversion_factor":0.5}]},
             "wind":[{"location":"Roof","properties":{"speed":{"value":5,"unit":"m/s"}}}],
             "ext_light":[{"value":200,"unit":"lux","description":"Desk"}]}
            """#)
        #expect(info.sensors.other["radiation"] == .object([
            "alpha": .array([.object(["value": .number(0.1), "unit": .string("µSv/h"), "conversion_factor": .number(0.5)])])]))
        #expect(info.sensors.other["wind"] == .array([.object([
            "location": .string("Roof"), "properties": .object([
                "speed": .object(["value": .number(5), "unit": .string("m/s")])])])]))
        #expect(info.sensors.other["ext_light"] == .array([.object([
            "value": .number(200), "unit": .string("lux"), "description": .string("Desk")])]))
    }

    @Test func genericDataKeepsJSONTypesIncludingNull() throws {
        let info = try decode(#"""
            {"ext_null":null,"ext_values":[true,false,1,"1",null,{"value":[2,3]}]}
            """#)
        #expect(info.sensors.other["ext_null"] == .null)
        #expect(info.sensors.other["ext_values"] == .array([
            .boolean(true), .boolean(false), .number(1), .string("1"), .null,
            .object(["value": .array([.number(2), .number(3)])])]))
    }

    @Test func invalidKnownKindsAreNotReinterpretedAsGenericReadings() throws {
        let info = try decode(#"""
            {"temperature":[{"value":"warm"}],"humidity":{},"door_locked":null,
             "ext_note":"uninterpreted","ext_broken":[{"value":"bad"}]}
            """#)
        #expect(info.sensors.temperature.isEmpty)
        #expect(info.sensors.humidity.isEmpty)
        #expect(info.sensors.doorLocked.isEmpty)
        #expect(Set(info.sensors.other.keys) == ["ext_note", "ext_broken"])
        #expect(info.status == .open)
    }

    @Test func rejectsNonfiniteReadingsButKeepsValidSiblingsAndMetadata() throws {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        let info = try decode(#"""
            {"temperature":[{"value":"Infinity"},{"value":"-Infinity"},{"value":"NaN"},
                            {"value":20,"lastchange":"Infinity"},{"value":21}]}
            """#, decoder: decoder)
        #expect(info.sensors.temperature.map(\.value) == [20, 21])
        #expect(info.sensors.temperature.allSatisfy { $0.lastChange == nil })
    }

    @Test func sensorChangeTimeDoesNotRefreshDocumentObservation() throws {
        let info = try decode(#"""
            {"temperature":[{"value":20,"lastchange":9999999999.5},{"value":21,"lastchange":-0.5}]}
            """#)
        #expect(info.sensors.temperature.map(\.lastChange) == [
            Date(timeIntervalSince1970: 9_999_999_999.5), Date(timeIntervalSince1970: -0.5)])
        let receipt = Date(timeIntervalSince1970: 2_000)
        let stale = StatusObservation(value: info, timing: ObservationTiming(
            source: .direct, observedAt: Date(timeIntervalSince1970: 1_000), receivedAt: receipt))
        #expect(stale.timing.freshness(at: receipt) == .stale)
        #expect(stale.timing.currentStatus(stale.value.status, at: receipt) == .unknown)
        let unknown = ObservationTiming(source: .aggregator, observedAt: nil, receivedAt: receipt)
        #expect(unknown.freshness(at: receipt) == .unknown)
        #expect(unknown.currentStatus(info.status, at: receipt) == .unknown)
    }

    @Test func initializerDefaultsAndValueSemanticsStayCompatible() {
        let calendar = URL(string: "https://space.example/calendar.ics")!
        let old = SpaceInfo(name: "Space", calendar: calendar)
        #expect(old.sensors == SpaceInfo.Sensors())
        #expect(old.calendar == calendar)
        let reading = SpaceInfo.Sensor(value: 20.0, unit: "°C", location: "Lab")
        let sensors = SpaceInfo.Sensors(temperature: [reading], doorLocked: [.init(value: false)],
                                       other: ["ext_note": .string("raw")])
        let info = SpaceInfo(name: "Space", sensors: sensors)
        var copy = info
        copy.sensors.temperature[0].value = 21
        #expect(info.sensors.temperature[0].value == 20)
        #expect(copy != info)
        #expect(Set([info, copy, info]).count == 2)
    }

    @Test func sensorsDoNotMaskMissingRequiredSpaceName() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SpaceInfo.self, from: Data(#"{"sensors":{"temperature":[{"value":20}]}}"#.utf8))
        }
    }
}
