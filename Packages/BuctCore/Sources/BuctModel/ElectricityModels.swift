import Foundation

public struct ElectricityRoomTarget: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(schoolId)::\(roomId)" }
    public let schoolId: String
    public let campusName: String
    public let buildingId: String
    public let buildingName: String
    public let floorId: String
    public let floorName: String
    public let roomId: String
    public let roomName: String
    public let meterType: String

    public init(
        schoolId: String,
        campusName: String,
        buildingId: String = "",
        buildingName: String = "",
        floorId: String = "",
        floorName: String = "",
        roomId: String,
        roomName: String,
        meterType: String = ""
    ) {
        self.schoolId = schoolId
        self.campusName = campusName
        self.buildingId = buildingId
        self.buildingName = buildingName
        self.floorId = floorId
        self.floorName = floorName
        self.roomId = roomId
        self.roomName = roomName
        self.meterType = meterType
    }

    public var displayTitle: String {
        let parts = [campusName, buildingName, roomName].filter { !$0.isEmpty }
        let base = parts.joined(separator: " · ")
        if !meterType.isEmpty && !roomName.contains(meterType) {
            return "\(base)（\(meterType)）"
        }
        return base.isEmpty ? roomId : base
    }
}

public struct ElectricityReading: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(schoolId)::\(roomId)" }
    public let schoolId: String
    public let roomId: String
    public let campusName: String
    public let buildingName: String
    public let floorName: String
    public let roomName: String
    public let meterType: String
    public let balanceText: String
    public let balanceValue: Double?
    public let unit: String
    public let accountStatus: String
    public let queriedAt: Int64
    public let fromCache: Bool

    public init(
        schoolId: String,
        roomId: String,
        campusName: String = "",
        buildingName: String = "",
        floorName: String = "",
        roomName: String = "",
        meterType: String = "",
        balanceText: String = "",
        balanceValue: Double? = nil,
        unit: String = "元",
        accountStatus: String = "1",
        queriedAt: Int64 = 0,
        fromCache: Bool = false
    ) {
        self.schoolId = schoolId
        self.roomId = roomId
        self.campusName = campusName
        self.buildingName = buildingName
        self.floorName = floorName
        self.roomName = roomName
        self.meterType = meterType
        self.balanceText = balanceText
        self.balanceValue = balanceValue
        self.unit = unit
        self.accountStatus = accountStatus
        self.queriedAt = queriedAt
        self.fromCache = fromCache
    }
}

public struct ElectricitySnapshot: Codable, Sendable, Equatable {
    public var targets: [ElectricityRoomTarget]
    public var readings: [ElectricityReading]
    public var lowBalanceThreshold: Double

    public init(
        targets: [ElectricityRoomTarget] = [],
        readings: [ElectricityReading] = [],
        lowBalanceThreshold: Double = 20.0
    ) {
        self.targets = targets
        self.readings = readings
        self.lowBalanceThreshold = lowBalanceThreshold
    }
}

public struct ElectricityRoomOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String { roomId }
    public let roomId: String
    public let name: String
    public let meterType: String

    enum CodingKeys: String, CodingKey {
        case roomId = "roomid"
        case name
        case meterType
    }

    public init(roomId: String, name: String, meterType: String = "") {
        self.roomId = roomId
        self.name = name
        self.meterType = meterType
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.roomId = (try? c.decode(String.self, forKey: .roomId)) ?? ""
        self.name = (try? c.decode(String.self, forKey: .name)) ?? ""
        self.meterType = (try? c.decode(String.self, forKey: .meterType)) ?? ""
    }
}

public struct ElectricityFloorOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String { floorId }
    public let floorId: String
    public let name: String
    public let rooms: [ElectricityRoomOption]

    enum CodingKeys: String, CodingKey {
        case floorId = "floorid"
        case name
        case rooms
    }

    public init(floorId: String, name: String, rooms: [ElectricityRoomOption]) {
        self.floorId = floorId
        self.name = name
        self.rooms = rooms
    }
}

public struct ElectricityBuildingOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String { buildingId }
    public let buildingId: String
    public let name: String
    public let floors: [ElectricityFloorOption]

    enum CodingKeys: String, CodingKey {
        case buildingId = "buildingid"
        case name
        case floors
    }

    public init(buildingId: String, name: String, floors: [ElectricityFloorOption]) {
        self.buildingId = buildingId
        self.name = name
        self.floors = floors
    }
}

public struct ElectricityCampusOption: Codable, Sendable, Equatable, Identifiable {
    public var id: String { schoolId }
    public let schoolId: String
    public let name: String
    public let hasMeterType: Bool
    public let buildings: [ElectricityBuildingOption]

    enum CodingKeys: String, CodingKey {
        case schoolId = "schoolid"
        case name
        case hasMeterType
        case buildings
    }

    public init(schoolId: String, name: String, hasMeterType: Bool, buildings: [ElectricityBuildingOption]) {
        self.schoolId = schoolId
        self.name = name
        self.hasMeterType = hasMeterType
        self.buildings = buildings
    }
}

public struct ElectricityRoomCatalog: Codable, Sendable, Equatable {
    public let factorycode: String
    public let crawledAt: String
    public let campuses: [ElectricityCampusOption]

    public init(factorycode: String = "E005", crawledAt: String = "", campuses: [ElectricityCampusOption] = []) {
        self.factorycode = factorycode
        self.crawledAt = crawledAt
        self.campuses = campuses
    }

    public static func baseRoomName(_ rawName: String) -> String {
        var s = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["照明", "空调", "（照明）", "（空调）", "(照明)", "(空调)"] {
            if s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return s
    }
}
