import Foundation

extension Data {
    package func base64URLEncodedString() -> String {
        String(base64EncodedString().compactMap { char in
            switch char {
            case "+": "-"
            case "/": "_"
            case "=": nil
            default: char
            }
        })
    }
}

extension String {
    package func base64URLDecodedData() -> Data? {
        var s = String(map { char in
            switch char {
            case "-": "+"
            case "_": "/"
            default: char
            }
        })
        s.append(String(repeating: "=", count: (4 - s.count % 4) % 4))
        return Data(base64Encoded: s)
    }
}
