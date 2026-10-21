//
//  JSONImportOptions.swift
//  JSONImportPlugin
//

import Foundation
import TableProPluginKit

struct JSONImportOptions: Equatable, Codable, RowImportOptions {
    var errorHandling: ImportErrorHandling = .stopAndRollback
    var wrapInTransaction: Bool = true
    var deleteExistingRows: Bool = false
}
