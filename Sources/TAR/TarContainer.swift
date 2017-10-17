// Copyright (c) 2017 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation

/// Provides open function for TAR containers.
public class TarContainer: Container {

    /**
     Processes TAR container and returns an array of `TarEntry`.

     - Important: The order of entries is defined by TAR container and,
     particularly, by the creator of a given TAR container.
     It is likely that directories will be encountered earlier than files stored in those directories,
     but one SHOULD NOT rely on any particular order.

     - Parameter container: TAR container's data.

     - Throws: `TarError`, which may indicate that either container is damaged or it might not be TAR container at all.

     - Returns: Array of `TarEntry` as an array of `ContainerEntry`.
     */
    public static func open(container data: Data) throws -> [TarEntry] {
        // First, if the TAR container contains only header, it should be at least 512 bytes long.
        // So we have to check this.
        guard data.count >= 512 else { throw TarError.tooSmallFileIsPassed }

        /// Object with input data which supports convenient work with bit shifts.
        let pointerData = DataWithPointer(data: data)

        var output = [TarEntry]()

        var lastGlobalExtendedHeader: TarExtendedHeader?
        var lastLocalExtendedHeader: TarExtendedHeader?
        var longLinkName: String?
        var longName: String?

        while true {
            // Container ends with two zero-filled records.
            if pointerData.data[pointerData.index..<pointerData.index + 1024] == Data(count: 1024) {
                break
            }
            
            // Check for GNU LongName or LongLinkName.
            let fileTypeIndicator = pointerData.data[pointerData.index + 156]
            if fileTypeIndicator == 75 /* "K" */ || fileTypeIndicator == 76 /* "L" */ {
                // Jump to "size" field of header.
                pointerData.index += 124
                guard let size = Int(try pointerData.nullSpaceEndedAsciiString(cutoff: 12))?.octalToDecimal()
                    else { throw TarError.fieldIsNotNumber }
                
                // Jump to the start of data
                pointerData.index += 376
                let dataStartIndex = pointerData.index
                let longPath = try pointerData.nullEndedAsciiString(cutoff: size)
                
                if fileTypeIndicator == 75 /* "K" */ {
                    longLinkName = longPath
                } else {
                    longName = longPath
                }
                pointerData.index = dataStartIndex + size.roundTo512()
                continue
            }

            let info = try TarEntryInfo(pointerData, lastGlobalExtendedHeader, lastLocalExtendedHeader,
                                        longName, longLinkName)

            // File data
            let dataStartIndex = info.blockStartIndex + 512
            let dataEndIndex = dataStartIndex + info.size!
            let entryData = data[dataStartIndex..<dataEndIndex]
            pointerData.index = dataEndIndex - info.size! + info.size!.roundTo512()

            let entry = TarEntry(info, entryData)

            if info.isGlobalExtendedHeader {
                lastGlobalExtendedHeader = try TarExtendedHeader(entry.data)
            } else if info.isLocalExtendedHeader {
                lastLocalExtendedHeader = try TarExtendedHeader(entry.data)
            } else {
                output.append(entry)
                lastLocalExtendedHeader = nil
                longName = nil
                longLinkName = nil
            }
        }

        return output
    }

    public static func info(container data: Data) throws -> [TarEntryInfo] {
        // First, if the TAR container contains only header, it should be at least 512 bytes long.
        // So we have to check this.
        guard data.count >= 512 else { throw TarError.tooSmallFileIsPassed }
        
        /// Object with input data which supports convenient work with bit shifts.
        let pointerData = DataWithPointer(data: data)
        
        var output = [TarEntryInfo]()
        
        var lastGlobalExtendedHeader: TarExtendedHeader?
        var lastLocalExtendedHeader: TarExtendedHeader?
        var longLinkName: String?
        var longName: String?

        // TODO: First, populate infos, then get data in second loop.
        while true {
            // Container ends with two zero-filled records.
            if pointerData.data[pointerData.index..<pointerData.index + 1024] == Data(count: 1024) {
                break
            }
            
            // Check for GNU LongName or LongLinkName.
            // TODO: Include into TarEntryInfo.
            let fileTypeIndicator = pointerData.data[pointerData.index + 156]
            if fileTypeIndicator == 75 /* "K" */ || fileTypeIndicator == 76 /* "L" */ {
                // Jump to "size" field of header.
                pointerData.index += 124
                guard let size = Int(try pointerData.nullSpaceEndedAsciiString(cutoff: 12))?.octalToDecimal()
                    else { throw TarError.fieldIsNotNumber }
                
                // Jump to the start of data
                pointerData.index += 376
                let dataStartIndex = pointerData.index
                let longPath = try pointerData.nullEndedAsciiString(cutoff: size)
                
                if fileTypeIndicator == 75 /* "K" */ {
                    longLinkName = longPath
                } else {
                    longName = longPath
                }
                pointerData.index = dataStartIndex + size.roundTo512()
                continue
            }
            
            let info = try TarEntryInfo(pointerData, lastGlobalExtendedHeader, lastLocalExtendedHeader,
                                        longName, longLinkName)
            
            if info.isGlobalExtendedHeader {
                let dataStartIndex = info.blockStartIndex + 512
                let dataEndIndex = dataStartIndex + info.size!
                let headerData = data[dataStartIndex..<dataEndIndex]
                pointerData.index = dataEndIndex - info.size! + info.size!.roundTo512()

                lastGlobalExtendedHeader = try TarExtendedHeader(headerData)
            } else if info.isLocalExtendedHeader {
                let dataStartIndex = info.blockStartIndex + 512
                let dataEndIndex = dataStartIndex + info.size!
                let headerData = data[dataStartIndex..<dataEndIndex]
                pointerData.index = dataEndIndex - info.size! + info.size!.roundTo512()

                lastLocalExtendedHeader = try TarExtendedHeader(headerData)
            } else {
                // Skip file data.
                pointerData.index = info.blockStartIndex + 512 + info.size!.roundTo512()
                output.append(info)
                lastLocalExtendedHeader = nil
                longName = nil
                longLinkName = nil
            }
        }
        
        return output
    }

}
