// Copyright (c) 2017 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation

/// Provides compression and decompression functions for Deflate algorithm.
public class Deflate: DecompressionAlgorithm {

    struct Constants {
        static let codeLengthOrders: [Int] =
            [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

        /// - Warning: Substract 257 from index!
        static let lengthBase: [Int] =
            [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35,
             43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]

        static let distanceBase: [Int] =
            [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
             257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
             8193, 12289, 16385, 24577]

        static let lengthCode: [Int] =
            [257, 258, 259, 260, 261, 262, 263, 264, 265, 265, 266, 266, 267, 267, 268, 268,
             269, 269, 269, 269, 270, 270, 270, 270, 271, 271, 271, 271, 272, 272, 272, 272,
             273, 273, 273, 273, 273, 273, 273, 273, 274, 274, 274, 274, 274, 274, 274, 274,
             275, 275, 275, 275, 275, 275, 275, 275, 276, 276, 276, 276, 276, 276, 276, 276,
             277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277, 277,
             278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278, 278,
             279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279, 279,
             280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280, 280,
             281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281,
             281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281, 281,
             282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282,
             282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282, 282,
             283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283,
             283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283, 283,
             284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284,
             284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 284, 285]
    }

    /**
     Decompresses `data` using Deflate algortihm.

     If `data` is not actually compressed with Deflate, `DeflateError` will be thrown.

     - Note: This function is specification compliant.

     - Parameter data: Data compressed with Deflate.

     - Throws: `DeflateError` if unexpected byte (bit) sequence was encountered in `data`.
     It may indicate that either data is damaged or it might not be compressed with Deflate at all.

     - Returns: Decompressed data.
     */
    public static func decompress(data: Data) throws -> Data {
        /// Object with input data which supports convenient work with bit shifts.
        var pointerData = DataWithPointer(data: data, bitOrder: .reversed)
        return Data(bytes: try decompress(&pointerData))
    }

    static func decompress(_ pointerData: inout DataWithPointer) throws -> [UInt8] {
        /// An array for storing output data
        var out: [UInt8] = []

        while true {
            /// Is this a last block?
            let isLastBit = pointerData.bit()
            /// Type of the current block.
            let blockType = [UInt8](pointerData.bits(count: 2).reversed())

            if blockType == [0, 0] { // Uncompressed block.
                pointerData.skipUntilNextByte()
                /// Length of the uncompressed data.
                let length = pointerData.intFromBits(count: 16)
                /// 1-complement of the length.
                let nlength = pointerData.intFromBits(count: 16)
                // Check if lengths are OK (nlength should be a 1-complement of length).
                guard length & nlength == 0 else { throw DeflateError.wrongUncompressedBlockLengths }
                // Process uncompressed data into the output
                for _ in 0..<length {
                    out.append(pointerData.alignedByte())
                }
            } else if blockType == [1, 0] || blockType == [0, 1] {
                // Block with Huffman coding (either static or dynamic)

                // Declaration of Huffman trees which will be populated and used later.
                // There are two alphabets in use and each one needs a Huffman tree.

                /// Huffman tree for literal and length symbols/codes.
                var mainLiterals: HuffmanTree
                /// Huffman tree for backward distance symbols/codes.
                var mainDistances: HuffmanTree

                if blockType == [0, 1] { // Static Huffman
                    // In this case codes for literals and distances are fixed.
                    // Bootstraps for trees (first element in pair is code, second is number of bits).
                    let staticHuffmanBootstrap = [[0, 8], [144, 9], [256, 7], [280, 8], [288, -1]]
                    let staticHuffmanLengthsBootstrap = [[0, 5], [32, -1]]
                    // Initialize trees from these bootstraps.
                    mainLiterals = HuffmanTree(bootstrap: staticHuffmanBootstrap, &pointerData)
                    mainDistances = HuffmanTree(bootstrap: staticHuffmanLengthsBootstrap, &pointerData)
                } else { // Dynamic Huffman
                    // In this case there are Huffman codes for two alphabets in data right after block header.
                    // Each code defined by a sequence of code lengths (which are compressed themselves with Huffman).

                    /// Number of literals codes.
                    let literals = pointerData.intFromBits(count: 5) + 257
                    /// Number of distances codes.
                    let distances = pointerData.intFromBits(count: 5) + 1
                    /// Number of code lengths codes.
                    let codeLengthsLength = pointerData.intFromBits(count: 4) + 4

                    // Read code lengths codes.
                    // Moreover, they are stored in a very specific order, 
                    //  defined by HuffmanTree.Constants.codeLengthOrders.
                    var lengthsForOrder = Array(repeating: 0, count: 19)
                    for i in 0..<codeLengthsLength {
                        lengthsForOrder[Constants.codeLengthOrders[i]] = pointerData.intFromBits(count: 3)
                    }
                    /// Huffman tree for code lengths. Each code in the main alphabets is coded with this tree.
                    let dynamicCodes = HuffmanTree(lengthsToOrder: lengthsForOrder, &pointerData)

                    // Now we need to read codes (code lengths) for two main alphabets (trees).
                    var codeLengths: [Int] = []
                    var n = 0
                    while n < (literals + distances) {
                        // Finding next Huffman tree's symbol in data.
                        let symbol = dynamicCodes.findNextSymbol()
                        guard symbol != -1 else { throw DeflateError.symbolNotFound }

                        let count: Int
                        let what: Int
                        if symbol >= 0 && symbol <= 15 {
                            // It is a raw code length.
                            count = 1
                            what = symbol
                        } else if symbol == 16 {
                            // Copy previous code length 3 to 6 times.
                            // Next two bits show how many times we need to copy.
                            count = pointerData.intFromBits(count: 2) + 3
                            what = codeLengths.last!
                        } else if symbol == 17 {
                            // Repeat code length 0 for from 3 to 10 times.
                            // Next three bits show how many times we need to copy.
                            count = pointerData.intFromBits(count: 3) + 3
                            what = 0
                        } else if symbol == 18 {
                            // Repeat code length 0 for from 11 to 138 times.
                            // Next seven bits show how many times we need to do this.
                            count = pointerData.intFromBits(count: 7) + 11
                            what = 0
                        } else {
                            throw DeflateError.wrongSymbol
                        }
                        for _ in 0..<count {
                            codeLengths.append(what)
                        }
                        n += count
                    }
                    // We have read codeLengths for both trees at once.
                    // Now we need to split them and make corresponding trees.
                    mainLiterals = HuffmanTree(lengthsToOrder: Array(codeLengths[0..<literals]),
                                               &pointerData)
                    mainDistances = HuffmanTree(lengthsToOrder: Array(codeLengths[literals..<codeLengths.count]),
                                                &pointerData)
                }

                // Main loop of data decompression.
                while true {
                    // Read next symbol from data.
                    // It will be either literal symbol or a length of (previous) data we will need to copy.
                    let nextSymbol = mainLiterals.findNextSymbol()
                    guard nextSymbol != -1 else { throw DeflateError.symbolNotFound }

                    if nextSymbol >= 0 && nextSymbol <= 255 {
                        // It is a literal symbol so we add it straight to the output data.
                        out.append(nextSymbol.toUInt8())
                    } else if nextSymbol == 256 {
                        // It is a symbol indicating the end of data.
                        break
                    } else if nextSymbol >= 257 && nextSymbol <= 285 {
                        // It is a length symbol.
                        // Depending on the value of nextSymbol there might be additional bits in data,
                        // which we need to add to nextSymbol to get the full length.
                        let extraLength = (257 <= nextSymbol && nextSymbol <= 260) || nextSymbol == 285 ?
                            0 : (((nextSymbol - 257) >> 2) - 1)
                        // Actually, nextSymbol is not a starting value of length,
                        //  but an index for special array of starting values.
                        let length = Constants.lengthBase[nextSymbol - 257] +
                            pointerData.intFromBits(count: extraLength)

                        // Then we need to get distance code.
                        let distanceCode = mainDistances.findNextSymbol()
                        guard distanceCode != -1 else { throw DeflateError.symbolNotFound }
                        guard distanceCode >= 0 && distanceCode <= 29
                            else { throw DeflateError.wrongSymbol }

                        // Again, depending on the distanceCode's value there might be additional bits in data,
                        // which we need to combine with distanceCode to get the actual distance.
                        let extraDistance = distanceCode == 0 || distanceCode == 1 ? 0 : ((distanceCode >> 1) - 1)
                        // And yes, distanceCode is not a first part of distance but rather an index for special array.
                        let distance = Constants.distanceBase[distanceCode] +
                            pointerData.intFromBits(count: extraDistance)

                        // We should repeat last 'distance' amount of data.
                        // The amount of times we do this is round(length / distance).
                        // length actually indicates the amount of data we get from this nextSymbol.
                        let repeatCount: Int = length / distance
                        let count = out.count
                        for _ in 0..<repeatCount {
                            for i in count - distance..<count {
                                out.append(out[i])
                            }
                        }
                        // Now we deal with the remainings.
                        if length - distance * repeatCount == distance {
                            for i in out.count - distance..<out.count {
                                out.append(out[i])
                            }
                        } else {
                            for i in out.count - distance..<out.count + length - distance * (repeatCount + 1) {
                                out.append(out[i])
                            }
                        }
                    } else {
                        throw DeflateError.wrongSymbol
                    }
                }

            } else {
                throw DeflateError.wrongBlockType
            }

            // End the cycle if it was the last block.
            if isLastBit == 1 { break }
        }

        return out
    }

}
