#!/usr/bin/env xcrun swift
//
//  main.swift
//  AbandonedStrings
//
//  Created by Joshua Smith on 2/1/16.
//  Copyright © 2016 iJoshSmith. All rights reserved.
//

/*
 For overview and usage information refer to https://github.com/ijoshsmith/abandoned-strings
 */

import Foundation

// MARK: - File processing

let dispatchGroup = DispatchGroup.init()
let serialWriterQueue = DispatchQueue.init(label: "writer")
let standardOut: OutputStream = OutputStream(streamType: .stdOut, stringEncoding: .utf8)
let standardError: OutputStream = OutputStream(streamType: .stdErr, stringEncoding: .utf8)

func findFilesIn(_ directories: [String], withExtensions extensions: [String]) -> [String] {
    let fileManager = FileManager.default
    var files = [String]()
    for directory in directories {
        guard let enumerator: FileManager.DirectoryEnumerator = fileManager.enumerator(atPath: directory) else {
            standardError.write("Failed to create enumerator for directory: \(directory)")
            return []
        }
        while let path = enumerator.nextObject() as? String {
            let fileExtension = (path as NSString).pathExtension.lowercased()
            if extensions.contains(fileExtension) {
                let fullPath = (directory as NSString).appendingPathComponent(path)
                files.append(fullPath)
            }
        }
    }
    return files
}

func contentsOfFile(_ filePath: String) -> String {
    do {
        return try String(contentsOfFile: filePath)
    }
    catch {
        standardError.forceWriteToStdErr("Cannot find file at path: \(filePath)")
        exit(1)
    }
}

func concatenateAllSourceCodeIn(_ directories: [String], withStoryboard: Bool) -> String {
    var extensions = ["h", "m", "swift", "jsbundle"]
    if withStoryboard {
        extensions.append("storyboard")
    }
    let sourceFiles = findFilesIn(directories, withExtensions: extensions)
    return sourceFiles.reduce("") { (accumulator, sourceFile) -> String in
        return accumulator + contentsOfFile(sourceFile)
    }
}

// MARK: - Identifier extraction

let doubleQuote = "\""

func extractStringIdentifiersFrom(_ stringsFile: String) -> [String] {
    return contentsOfFile(stringsFile)
        .components(separatedBy: "\n")
        .map    { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
        .filter { $0.hasPrefix(doubleQuote) }
        .map    { extractStringIdentifierFromTrimmedLine($0) }
}

func extractStringIdentifierFromTrimmedLine(_ line: String) -> String {
    let indexAfterFirstQuote = line.index(after: line.startIndex)
    let lineWithoutFirstQuote = line[indexAfterFirstQuote...]
    let endIndex = lineWithoutFirstQuote.firstIndex(of:"\"")!
    let identifier = lineWithoutFirstQuote[..<endIndex]
    return String(identifier)
}

// MARK: - Abandoned identifier detection

func findStringIdentifiersIn(_ stringsFile: String, abandonedBySourceCode sourceCode: String) -> [String] {
    return extractStringIdentifiersFrom(stringsFile).filter { identifier in
        let quotedIdentifier = "\"\(identifier)\""
        let quotedIdentifierForStoryboard = "\"@\(identifier)\""
        let signalQuotedIdentifierForJs = "'\(identifier)'"
        let isAbandoned = (sourceCode.contains(quotedIdentifier) == false && sourceCode.contains(quotedIdentifierForStoryboard) == false &&
            sourceCode.contains(signalQuotedIdentifierForJs) == false)
        return isAbandoned
    }
}

func stringsFile(_ stringsFile: String, without identifiers: [String]) -> String {
    return contentsOfFile(stringsFile)
        .components(separatedBy: "\n")
        .filter({ (line) in
            guard line.hasPrefix(doubleQuote) else { return true } // leave non-strings lines like comments in
            let lineIdentifier = extractStringIdentifierFromTrimmedLine(line.trimmingCharacters(in: CharacterSet.whitespaces))
            return identifiers.contains(lineIdentifier) == false
        })
        .joined(separator: "\n")
}

typealias StringsFileToAbandonedIdentifiersMap = [String: [String]]

func findAbandonedIdentifiersIn(_ rootDirectories: [String], withStoryboard: Bool) -> StringsFileToAbandonedIdentifiersMap {
    var map = StringsFileToAbandonedIdentifiersMap()
    let sourceCode = concatenateAllSourceCodeIn(rootDirectories, withStoryboard: withStoryboard)
    let stringsFiles = findFilesIn(rootDirectories, withExtensions: ["strings"])
    for stringsFile in stringsFiles {
        dispatchGroup.enter()
        DispatchQueue.global().async {
            let abandonedIdentifiers = findStringIdentifiersIn(stringsFile, abandonedBySourceCode: sourceCode)
            if abandonedIdentifiers.isEmpty == false {
                serialWriterQueue.async {
                    map[stringsFile] = abandonedIdentifiers
                    dispatchGroup.leave()
                }
            } else {
                standardOut.write("\(stringsFile) has no abandonedIdentifiers")
                dispatchGroup.leave()
            }
        }
    }
    dispatchGroup.wait()
    return map
}

// MARK: - Engine

func getRootDirectories() -> [String]? {
    var c = [String]()
    for arg in CommandLine.arguments {
        c.append(arg)
    }
    c.remove(at: 0)
    if isOptionalParameterForStoryboardAvailable() {
        c.removeLast()
    }
    if isOptionaParameterForWritingAvailable() {
        c.remove(at: c.firstIndex(of: "write")!)
    }
    return c
}

func isOptionalParameterForStoryboardAvailable() -> Bool {
    return CommandLine.arguments.last == "storyboard"
}

func isOptionaParameterForWritingAvailable() -> Bool {
    return CommandLine.arguments.contains("write")
}

func displayAbandonedIdentifiersInMap(_ map: StringsFileToAbandonedIdentifiersMap) {
    for file in map.keys.sorted() {
        standardOut.write("\(file)")
        for identifier in map[file]!.sorted() {
            standardOut.write("  \(identifier)")
        }
        standardOut.write("")
    }
}

if let rootDirectories = getRootDirectories() {
    standardOut.write("Searching for abandoned resource strings…")
    let withStoryboard = isOptionalParameterForStoryboardAvailable()
    let map = findAbandonedIdentifiersIn(rootDirectories, withStoryboard: withStoryboard)
    if map.isEmpty {
        standardOut.write("No abandoned resource strings were detected.")
    }
    else {
        standardOut.write("Abandoned resource strings were detected:")
        displayAbandonedIdentifiersInMap(map)
        
        if isOptionaParameterForWritingAvailable() {
            map.keys.forEach { (stringsFilePath) in
                standardOut.write("\n\nNow modifying \(stringsFilePath) ...")
                let updatedStringsFileContent = stringsFile(stringsFilePath, without: map[stringsFilePath]!)
                do {
                    try updatedStringsFileContent.write(toFile: stringsFilePath, atomically: true, encoding: .utf8)
                } catch {
                    standardError.write("ERROR writing file: \(stringsFilePath)")
                }
            }
        }
    }
} else {
    standardOut.write("Please provide the root directory for source code files as a command line argument.")
}
