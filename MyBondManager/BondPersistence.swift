//
//  BondPersistence.swift
//  MyBondManager
//
//  Created by Olivier on 19/04/2025.
//


//  BondPersistence.swift
//  MyBondManager
//
//  Created by Olivier on 17/04/2025.
//

import Foundation

/// A singleton responsible for loading/saving both active and matured bonds,
/// and for performing the one‑time migration of any newly matured bonds.
class BondPersistence {
    static let shared = BondPersistence()

    private let fileManager = FileManager.default
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = .prettyPrinted
        return e
    }()

    private var documentDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var activeURL: URL {
        documentDirectory.appendingPathComponent("bonds.json")
    }
    private var maturedURL: URL {
        documentDirectory.appendingPathComponent("matured_bonds.json")
    }

    // Allow calls from App entry‐point
    fileprivate init() {}

    /// Load the active bonds from disk (or return empty if none).
    func loadActiveBonds() -> [Bond] {
        do {
            let data = try Data(contentsOf: activeURL)
            let list = try decoder.decode([Bond].self, from: data)
            return list
        } catch {
            print("Failed to load active bonds: \(error)")
            return []
        }
    }

    /// Save the given active bonds array back to disk.
    func saveActiveBonds(_ list: [Bond]) {
        do {
            let data = try encoder.encode(list)
            try data.write(to: activeURL)
        } catch {
            print("Failed to save active bonds: \(error)")
        }
    }

    /// Load the matured bonds archive (or return empty if none).
    func loadMaturedBonds() -> [Bond] {
        do {
            let data = try Data(contentsOf: maturedURL)
            let list = try decoder.decode([Bond].self, from: data)
            return list
        } catch {
            print("Failed to load matured bonds: \(error)")
            return []
        }
    }

    /// Save the given matured bonds archive back to disk.
    func saveMaturedBonds(_ list: [Bond]) {
        do {
            let data = try encoder.encode(list)
            try data.write(to: maturedURL)
        } catch {
            print("Failed to save matured bonds: \(error)")
        }
    }

    /// **Migration step**:
    /// - Reads active bonds, filters out any whose maturityDate < today,
    /// - Appends them into the matured archive,
    /// - Writes both files back,
    /// - **Returns** the newly matured bonds.
    @discardableResult
    func migrateAndReturnNewlyMatured() -> [Bond] {
        let today = Calendar.current.startOfDay(for: Date())
        let active = loadActiveBonds()
        let (stillActive, newlyMatured) = active.partitioned { $0.maturityDate < today }

        guard !newlyMatured.isEmpty else {
            // nothing new matured
            return []
        }

        // 1) Append newly matured to the archive
        var archived = loadMaturedBonds()
        archived.append(contentsOf: newlyMatured)
        saveMaturedBonds(archived)

        // 2) Save back only the still‑active ones
        saveActiveBonds(stillActive)

        return newlyMatured
    }
}

// MARK: - Array partitioning helper

private extension Array {
    /// Returns (those for which `isMatured(element)==false`, those for which `==true`)
    func partitioned(_ isMatured: (Element) -> Bool) -> (keep: [Element], move: [Element]) {
        return self.reduce(into: (keep: [Element](), move: [Element]())) { result, element in
            if isMatured(element) {
                result.move.append(element)
            } else {
                result.keep.append(element)
            }
        }
    }
}
