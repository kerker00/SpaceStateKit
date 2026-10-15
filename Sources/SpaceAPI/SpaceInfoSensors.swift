import Foundation

extension SpaceInfo {
    /// A published reading. Units and optional metadata are preserved without conversion.
    /// Decoding requires a correctly typed value; nonfinite numeric readings are rejected.
    public struct Sensor<Value: Sendable & Hashable & Decodable>: Sendable, Hashable, Decodable {
        public var value: Value
        public var unit: String?
        public var location: String?
        public var name: String?
        public var description: String?
        /// Provider-reported value change, not measurement age, receipt or last attempt.
        public var lastChange: Date?

        private enum CodingKeys: String, CodingKey {
            case value, unit, location, name, description, lastchange
        }

        public init(value: Value, unit: String? = nil, location: String? = nil,
                    name: String? = nil, description: String? = nil, lastChange: Date? = nil) {
            self.value = value
            self.unit = unit
            self.location = location
            self.name = name
            self.description = description
            self.lastChange = lastChange
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try container.decode(Value.self, forKey: .value)
            if let number = value as? Double, !number.isFinite {
                throw DecodingError.dataCorruptedError(
                    forKey: .value, in: container, debugDescription: "Sensor value must be finite")
            }
            unit = container.lossy(String.self, forKey: .unit)
            location = container.lossy(String.self, forKey: .location)
            name = container.lossy(String.self, forKey: .name)
            description = container.lossy(String.self, forKey: .description)
            lastChange = container.lossyDate(forKey: .lastchange).flatMap {
                $0.timeIntervalSince1970.isFinite ? $0 : nil
            }
        }
    }

    /// Common sensor kinds have typed readings. Other kinds retain their JSON shape
    /// in `other`, including compound wind/radiation data and provider extensions.
    /// A broken entry is omitted without discarding its valid siblings or the space.
    public struct Sensors: Sendable, Hashable, Decodable {
        public var temperature: [Sensor<Double>]
        public var humidity: [Sensor<Double>]
        public var carbonDioxide: [Sensor<Double>]
        public var barometer: [Sensor<Double>]
        public var doorLocked: [Sensor<Bool>]
        public var peopleNowPresent: [Sensor<Double>]
        public var totalMemberCount: [Sensor<Double>]
        public var networkConnections: [Sensor<Double>]
        public var beverageSupply: [Sensor<Double>]
        public var powerConsumption: [Sensor<Double>]
        public var powerGeneration: [Sensor<Double>]
        /// Uninterpreted JSON for sensor kinds without a typed model. These values
        /// are not validated measurements, URLs or evidence of freshness.
        public var other: [String: SensorData]

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case temperature, humidity, barometer
            case carbonDioxide = "carbondioxide"
            case doorLocked = "door_locked"
            case peopleNowPresent = "people_now_present"
            case totalMemberCount = "total_member_count"
            case networkConnections = "network_connections"
            case beverageSupply = "beverage_supply"
            case powerConsumption = "power_consumption"
            case powerGeneration = "power_generation"
        }

        public init(
            temperature: [Sensor<Double>] = [], humidity: [Sensor<Double>] = [],
            carbonDioxide: [Sensor<Double>] = [], barometer: [Sensor<Double>] = [],
            doorLocked: [Sensor<Bool>] = [], peopleNowPresent: [Sensor<Double>] = [],
            totalMemberCount: [Sensor<Double>] = [], networkConnections: [Sensor<Double>] = [],
            beverageSupply: [Sensor<Double>] = [], powerConsumption: [Sensor<Double>] = [],
            powerGeneration: [Sensor<Double>] = [], other: [String: SensorData] = [:]
        ) {
            self.temperature = temperature
            self.humidity = humidity
            self.carbonDioxide = carbonDioxide
            self.barometer = barometer
            self.doorLocked = doorLocked
            self.peopleNowPresent = peopleNowPresent
            self.totalMemberCount = totalMemberCount
            self.networkConnections = networkConnections
            self.beverageSupply = beverageSupply
            self.powerConsumption = powerConsumption
            self.powerGeneration = powerGeneration
            self.other = other
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            temperature = container.lossyArray(Sensor<Double>.self, forKey: .temperature)
            humidity = container.lossyArray(Sensor<Double>.self, forKey: .humidity)
            carbonDioxide = container.lossyArray(Sensor<Double>.self, forKey: .carbonDioxide)
            barometer = container.lossyArray(Sensor<Double>.self, forKey: .barometer)
            doorLocked = container.lossyArray(Sensor<Bool>.self, forKey: .doorLocked)
            // Optional names/machines lists are deliberately not part of these readings.
            peopleNowPresent = container.lossyArray(Sensor<Double>.self, forKey: .peopleNowPresent)
            totalMemberCount = container.lossyArray(Sensor<Double>.self, forKey: .totalMemberCount)
            networkConnections = container.lossyArray(Sensor<Double>.self, forKey: .networkConnections)
            beverageSupply = container.lossyArray(Sensor<Double>.self, forKey: .beverageSupply)
            powerConsumption = container.lossyArray(Sensor<Double>.self, forKey: .powerConsumption)
            powerGeneration = container.lossyArray(Sensor<Double>.self, forKey: .powerGeneration)

            let raw = try decoder.container(keyedBy: SensorKey.self)
            let known = Set(CodingKeys.allCases.map(\.rawValue))
            other = [:]
            for key in raw.allKeys where !known.contains(key.stringValue) {
                if let data = try? raw.decode(SensorData.self, forKey: key) {
                    other[key.stringValue] = data
                }
            }
        }
    }

    /// JSON retained for sensor kinds without a typed model. No type coercion,
    /// unit inference or interpretation of provider-specific fields is performed.
    public indirect enum SensorData: Sendable, Hashable, Decodable {
        case number(Double)
        case boolean(Bool)
        case string(String)
        case array([SensorData])
        case object([String: SensorData])
        case null

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .boolean(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode(Double.self), value.isFinite {
                self = .number(value)
            } else if let value = try? container.decode([SensorData].self) {
                self = .array(value)
            } else if let value = try? container.decode([String: SensorData].self) {
                self = .object(value)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid sensor JSON")
            }
        }
    }
}

private struct SensorKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
