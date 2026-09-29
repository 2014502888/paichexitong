import Foundation

// MARK: - XLSX 导出
// 通过手写 OpenXML（SpreadsheetML）并自行打包 ZIP（store 模式）生成 .xlsx
enum ExternalXLSXExporter {

    static let columns: [String] = [
        "邮件单号",          // 1
        "失败",              // 2
        "异常",              // 3
        "撤单",              // 4
        "改址",              // 5
        "拒收",              // 6
        "重复",              // 7
        "最后更新时间",      // 8
        "当前物流状态",      // 9
        "状态代码",          // 10
        "物流行数",          // 11
        "历时",              // 12
        "耗时",              // 13
        "投递员",            // 14
        "所在省",            // 15
        "所在市",            // 16
        "所在机构",          // 17
        "机构代码",          // 18
        "收寄时间",          // 19
        "收寄信息",          // 20
        "收寄省份",          // 21
        "收寄城市",          // 22
        "收寄机构"           // 23
    ]

    static func defaultFileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return "物流查询_\(f.string(from: Date()))"
    }

    static func export(_ results: [ExternalMailResult]) -> Data {
        var rows: [[String]] = [columns]
        for r in results {
            let isFailed = r.status.isFailed
            let row: [String] = [
                r.mailNum,                                              // 1. 邮件单号
                isFailed ? "是" : "",                                  // 2. 失败
                r.isAbnormal ? "是" : "",                             // 3. 异常
                r.isCancelled ? "是" : "",                             // 4. 撤单
                r.isChangedAddr ? "是" : "",                           // 5. 改址
                r.isRejected ? "是" : "",                              // 6. 拒收
                r.isDuplicate ? "是" : "",                            // 7. 重复
                r.lastTime,                                             // 8. 最后更新时间
                r.statusText,                                           // 9. 当前物流状态
                isFailed ? "" : formatStatusCode(r.statusCode, lastRemark: r.statusText),             // 10. 状态代码（失败留空）
                isFailed ? "" : "\(r.traceLen)",                     // 11. 物流行数（失败留空）
                r.durationText,                                         // 12. 历时
                r.durationToDeliverText,                               // 13. 耗时
                r.sender,                                               // 14. 投递员
                r.province,                                             // 15. 所在省
                r.city,                                                 // 16. 所在市
                r.orgName,                                              // 17. 所在机构
                r.orgCode,                                              // 18. 机构代码
                r.acceptTime,                                           // 19. 收寄时间
                r.acceptInfo,                                           // 20. 收寄信息
                r.acceptProvince,                                       // 21. 收寄省份
                r.acceptCity,                                           // 22. 收寄城市
                r.acceptOrg                                             // 23. 收寄机构
            ]
            rows.append(row)
        }

        let files: [(name: String, data: Data)] = [
            ("[Content_Types].xml", Data(contentTypesXML.utf8)),
            ("_rels/.rels", Data(rootRelsXML.utf8)),
            ("xl/workbook.xml", Data(workbookXML.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRelsXML.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheetXML(rows: rows).utf8)),
            ("xl/styles.xml", Data(stylesXML.utf8))
        ]
        return ExternalSimpleZip.archive(files: files)
    }

    static func columnLetter(_ index: Int) -> String {
        var n = index + 1
        var s = ""
        while n > 0 {
            let rem = (n - 1) % 26
            s = String(UnicodeScalar(65 + rem)!) + s
            n = (n - 1) / 26
        }
        return s
    }

    static func sheetXML(rows: [[String]]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <cols>
        <col min="1" max="1" width="15" customWidth="1"/>
        <col min="2" max="2" width="8" customWidth="1"/>
        <col min="3" max="3" width="8" customWidth="1"/>
        <col min="4" max="4" width="8" customWidth="1"/>
        <col min="5" max="5" width="8" customWidth="1"/>
        <col min="6" max="6" width="8" customWidth="1"/>
        <col min="7" max="7" width="8" customWidth="1"/>
        <col min="8" max="8" width="19" customWidth="1"/>
        <col min="9" max="9" width="60" customWidth="1"/>
        <col min="10" max="10" width="10" customWidth="1"/>
        <col min="11" max="11" width="10" customWidth="1"/>
        <col min="12" max="12" width="15" customWidth="1"/>
        <col min="13" max="13" width="8" customWidth="1"/>
        </cols>
        <sheetData>
        """
        for (rowIndex, row) in rows.enumerated() {
            let r = rowIndex + 1
            xml += "<row r=\"\(r)\">"
            for (colIndex, cell) in row.enumerated() {
                let ref = "\(columnLetter(colIndex))\(r)"
                // 第 9 列（当前物流状态）靠左，其余全部居中
                let s = colIndex == 8 ? "2" : "1"
                xml += "<c r=\"\(ref)\" s=\"\(s)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXML(cell))</t></is></c>"
            }
            xml += "</row>"
        }
        xml += "</sheetData>"
        // 自动筛选：第一行所有列
        let lastColLetter = columnLetter((rows.first?.count ?? 1) - 1)
        xml += "<autoFilter ref=\"A1:\(lastColLetter)1\"/>"
        xml += "</worksheet>"
        return xml
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
    <Default Extension="xml" ContentType="application/xml"/>
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Results" sheetId="1" r:id="rId1"/></sheets></workbook>
    """

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    // 样式：s=1 居中，s=2 靠左（当前物流状态列用）
    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>
    <fills count="1"><fill><patternFill patternType="none"/></fill></fills>
    <borders count="1"><border/></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="left" vertical="center"/></xf>
    </cellXfs>
    </styleSheet>
    """

    static func escapeXML(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&":  out += "&amp;"
            case "<":  out += "&lt;"
            case ">":  out += "&gt;"
            case "\"": out += "&quot;"
            case "'":  out += "&apos;"
            default:   out.append(ch)
            }
        }
        return out
    }
}

// MARK: - 手写 ZIP 打包器（store 模式，无压缩）
struct ExternalSimpleZip {

    static func archive(files: [(name: String, data: Data)]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for file in files {
            let nameData = Data(file.name.utf8)
            let crc = crc32(file.data)
            let size = UInt32(file.data.count)

            var local = Data()
            local += uint32(0x04034b50)
            local += uint16(20)
            local += uint16(0x0800)
            local += uint16(0)
            local += uint16(0)
            local += uint16(0x21)
            local += uint32(crc)
            local += uint32(size)
            local += uint32(size)
            local += uint16(UInt16(nameData.count))
            local += uint16(0)
            local += nameData
            local += file.data
            output += local

            var central = Data()
            central += uint32(0x02014b50)
            central += uint16(20)
            central += uint16(20)
            central += uint16(0x0800)
            central += uint16(0)
            central += uint16(0)
            central += uint16(0x21)
            central += uint32(crc)
            central += uint32(size)
            central += uint32(size)
            central += uint16(UInt16(nameData.count))
            central += uint16(0)
            central += uint16(0)
            central += uint16(0)
            central += uint16(0)
            central += uint32(0)
            central += uint32(offset)
            central += nameData
            centralDirectory += central

            offset += UInt32(local.count)
        }

        var eocd = Data()
        eocd += uint32(0x06054b50)
        eocd += uint16(0)
        eocd += uint16(0)
        eocd += uint16(UInt16(files.count))
        eocd += uint16(UInt16(files.count))
        eocd += uint32(UInt32(centralDirectory.count))
        eocd += uint32(offset)
        eocd += uint16(0)

        return output + centralDirectory + eocd
    }

    private static func uint16(_ v: UInt16) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: MemoryLayout<UInt16>.size)
    }

    private static func uint32(_ v: UInt32) -> Data {
        var le = v.littleEndian
        return Data(bytes: &le, count: MemoryLayout<UInt32>.size)
    }

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            table[n] = c
        }
        return table
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
