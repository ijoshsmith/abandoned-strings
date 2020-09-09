//
//  OutputStream.swift
//  AbandonedStrings
//
//  Created by Andreas Hård on 2020-09-09.
//  Copyright © 2020 iJoshSmith. All rights reserved.
//

import Foundation

enum OutputStreamType {
    case stdOut
    case stdErr
    
    var fileHandle: FileHandle {
        switch self {
        case .stdOut:
            return FileHandle.standardOutput
        case .stdErr:
            return FileHandle.standardError
        }
    }
}

struct OutputStream: TextOutputStream {
    let stringEncoding: String.Encoding
    let streamType: OutputStreamType
    
    init(streamType: OutputStreamType,
         stringEncoding: String.Encoding) {
        self.streamType = streamType
        self.stringEncoding = stringEncoding
    }

    func write(_ string: String) {
        guard let data = string.data(using: stringEncoding) else {
            let errorString: String = "Failed to convert string: \"\(string)\" to Data using string encoding: \"\(stringEncoding)\""
            forceWriteToStdErr(errorString)
            return
        }
        
        streamType.fileHandle.write(data)
    }
    
    func forceWriteToStdErr(_ string: String) {
        guard let data = string.data(using: stringEncoding) else {
            fatalError("Failed to write to stderr with string: \(string)")
        }
        switch streamType {
        case .stdErr:
            streamType.fileHandle.write(data)
        case .stdOut:
            FileHandle.standardError.write(data)
        }
    }
}
