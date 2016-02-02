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

func findFilesIn(directory: String, withExtensions extensions: [String]) -> [String] {
    let fileManager = NSFileManager.defaultManager()
    guard let enumerator: NSDirectoryEnumerator = fileManager.enumeratorAtPath(directory) else {
        print("Failed to create enumerator for directory: \(directory)")
        return []
    }
    
    var files = [String]()
    while let path = enumerator.nextObject() as? String {
        let fileExtension = (path as NSString).pathExtension.lowercaseString
        if extensions.contains(fileExtension) {
            let fullPath = (directory as NSString).stringByAppendingPathComponent(path)
            files.append(fullPath)
        }
    }
    return files
}

func contentsOfFile(filePath: String) -> String {
    do    { return try String(contentsOfFile: filePath, encoding: NSUTF8StringEncoding) }
    catch { return "" }
}

func concatenateAllSourceCodeIn(directory: String) -> String {
    let sourceFiles = findFilesIn(directory, withExtensions: ["h", "m", "swift"])
    return sourceFiles.reduce("") { (accumulator, sourceFile) -> String in
        return accumulator + contentsOfFile(sourceFile)
    }
}

// MARK: - Identifier extraction

let doubleQuote = "\""

func extractStringIdentifiersFrom(stringsFile: String) -> [String] {
    return contentsOfFile(stringsFile)
        .componentsSeparatedByString("\n")
        .map    { $0.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceCharacterSet()) }
        .filter { $0.hasPrefix(doubleQuote) }
        .map    { extractStringIdentifierFromTrimmedLine($0) }
}

func extractStringIdentifierFromTrimmedLine(line: String) -> String {
    let indexAfterFirstQuote = line.startIndex.successor()
    let lineWithoutFirstQuote = line.substringFromIndex(indexAfterFirstQuote)
    let endQuoteRange = lineWithoutFirstQuote.rangeOfString(doubleQuote)!
    let identifierEndIndex = endQuoteRange.endIndex.predecessor()
    let identifier = lineWithoutFirstQuote.substringToIndex(identifierEndIndex)
    return identifier
}

func findIdentifiersInStringsFile(stringsFile: String, abandonedBySourceCode sourceCode: String) -> [String] {
    return extractStringIdentifiersFrom(stringsFile).filter { identifier in
        let quotedIdentifier = "\"\(identifier)\""
        let isAbandoned = sourceCode.containsString(quotedIdentifier) == false
        return isAbandoned
    }
}

// MARK: - Abandoned identifier detection & display

typealias StringsFileToAbandonedIdentifiersMap = [String: [String]]

func findAbandonedIdentifiersIn(rootDirectory: String) -> StringsFileToAbandonedIdentifiersMap {
    var map = StringsFileToAbandonedIdentifiersMap()
    let sourceCode = concatenateAllSourceCodeIn(rootDirectory)
    let stringsFiles = findFilesIn(rootDirectory, withExtensions: ["strings"])
    for stringsFile in stringsFiles {
        let abandonedIdentifiers = findIdentifiersInStringsFile(stringsFile, abandonedBySourceCode: sourceCode)
        if abandonedIdentifiers.isEmpty == false {
            map[stringsFile] = abandonedIdentifiers
        }
    }
    return map
}

func displayAbandonedIdentifiersInMap(map: StringsFileToAbandonedIdentifiersMap) {
    for file in map.keys.sort() {
        print("\(file)")
        for identifier in map[file]!.sort() {
            print("  \(identifier)")
        }
        print("")
    }
}

// MARK: - Engine

func getRootDirectory() -> String? {
    return Process.arguments.count == 2 ? Process.arguments[1] : nil
}

if let rootDirectory = getRootDirectory() {
    print("Searching for abandoned resource strings…")
    let map = findAbandonedIdentifiersIn(rootDirectory)
    if map.isEmpty {
        print("No abandoned resource strings were detected.")
    }
    else {
        print("Abandoned resource strings were detected:")
        displayAbandonedIdentifiersInMap(map)
    }
}
else {
    print("Please provide the root directory for source code files as a command line argument.")
}
