// Copyright (c) 2017 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation

class SevenZipCoder {

    let idSize: Int
    let isComplex: Bool
    let hasAttributes: Bool

    let id: [UInt8]

    let numInStreams: Int
    let numOutStreams: Int

    var propertiesSize: Int?
    var properties: [UInt8]?

    init(_ pointerData: DataWithPointer) throws {
        let flags = pointerData.byte()
        guard flags & 0xC0 == 0
            else { throw SevenZipError.reservedCodecFlags }
        idSize = (flags & 0x0F).toInt()
        isComplex = flags & 0x10 != 0
        hasAttributes = flags & 0x20 != 0

        guard flags & 0x80 == 0 else { throw SevenZipError.altMethodsNotSupported }

        id = pointerData.bytes(count: idSize)

        numInStreams = isComplex ? pointerData.szMbd().multiByteInteger : 1
        numOutStreams = isComplex ? pointerData.szMbd().multiByteInteger : 1

        if hasAttributes {
            propertiesSize = pointerData.szMbd().multiByteInteger
            properties = pointerData.bytes(count: propertiesSize!)
        }
    }
}

extension SevenZipCoder: Equatable {

    static func == (lhs: SevenZipCoder, rhs: SevenZipCoder) -> Bool {
        let propertiesEqual: Bool
        if lhs.properties == nil && rhs.properties == nil {
            propertiesEqual = true
        } else if lhs.properties != nil && rhs.properties != nil {
            propertiesEqual = lhs.properties! == rhs.properties!
        } else {
            propertiesEqual = false
        }
        return lhs.id == rhs.id && lhs.numInStreams == rhs.numInStreams &&
            lhs.numOutStreams == rhs.numOutStreams && propertiesEqual
    }

}