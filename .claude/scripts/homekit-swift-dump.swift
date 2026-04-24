#!/usr/bin/swift
// homekit-swift-dump.swift — Dump HomeKit accessories using Swift HomeKit framework
// Run: swift .claude/scripts/homekit-swift-dump.swift

import Foundation
import HomeKit

class HKDumper: NSObject, HMHomeManagerDelegate {
    var manager: HMHomeManager!
    var completed = false

    override init() {
        super.init()
        manager = HMHomeManager()
        manager.delegate = self
    }

    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        var output: [String: Any] = [
            "dumped_at": ISO8601DateFormatter().string(from: Date()),
            "homes": []
        ]

        var homes: [[String: Any]] = []

        for home in manager.homes {
            var homeDict: [String: Any] = [
                "name": home.name,
                "is_primary": home.isPrimary,
                "rooms": [],
                "accessories": []
            ]

            var rooms: [[String: Any]] = []

            // Default room (unassigned)
            let defaultRoom = home.roomForEntireHome()
            if !defaultRoom.accessories.isEmpty {
                rooms.append(dumpRoom(defaultRoom))
            }

            for room in home.rooms {
                rooms.append(dumpRoom(room))
            }
            homeDict["rooms"] = rooms

            // All accessories flat list
            homeDict["all_accessories"] = home.accessories.map { dumpAccessory($0) }

            homes.append(homeDict)
        }

        output["homes"] = homes

        if let data = try? JSONSerialization.data(withJSONObject: output, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }

        completed = true
    }

    func dumpRoom(_ room: HMRoom) -> [String: Any] {
        return [
            "name": room.name,
            "accessories": room.accessories.map { dumpAccessory($0) }
        ]
    }

    func dumpAccessory(_ a: HMAccessory) -> [String: Any] {
        var dict: [String: Any] = [
            "name": a.name,
            "reachable": a.isReachable,
            "room": a.room?.name ?? "unassigned",
            "category": a.category.categoryType.rawValue,
            "identifier": a.uniqueIdentifier.uuidString,
            "services": []
        ]

        var services: [[String: Any]] = []
        for service in a.services {
            var svcDict: [String: Any] = [
                "name": service.name,
                "type": service.serviceType,
                "is_primary": service.isPrimaryService,
                "characteristics": []
            ]

            var chars: [[String: Any]] = []
            for c in service.characteristics {
                var cDict: [String: Any] = [
                    "type": c.characteristicType,
                    "description": c.localizedDescription,
                    "properties": c.properties,
                ]
                if let v = c.value {
                    cDict["value"] = "\(v)"
                }
                chars.append(cDict)
            }
            svcDict["characteristics"] = chars
            services.append(svcDict)
        }
        dict["services"] = services

        return dict
    }
}

let dumper = HKDumper()
let deadline = Date(timeIntervalSinceNow: 15)
while !dumper.completed && Date() < deadline {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
}

if !dumper.completed {
    let error = ["error": "Timeout waiting for HomeKit - may need HomeKit entitlement or TCC permission"]
    if let data = try? JSONSerialization.data(withJSONObject: error, options: .prettyPrinted),
       let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}
