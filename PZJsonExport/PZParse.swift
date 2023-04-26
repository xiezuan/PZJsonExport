//
//  PZParse.swift
//  PZJsonExport
//
//  Created by Pace.Z on 2018/4/14.
//  Copyright © 2018年 z. All rights reserved.
//

import Cocoa
import SwiftyJSON
import AddressBook

class PZJsonInfo {
    
    static let shared = PZJsonInfo()
    
    var rootClassName: String = "RootClass"
    var classPrefix: String?
    
    var classNames: [String] = []
    /// 字典中的数组映射表，key: 当前字典名, value 对应的数组名
    var mappingTable: [String:Array<String>] = [String: Array]()
    /// 关键字替换映射表，key 是类名，value 是对应关系数组.
    /// 如：id -> idField, value 是 [@"idField":@"id"]， key 是 A（类名）
    var mappingKeywordsTable: [String: Array<String>] = [String: Array]()
    /// key: className, value: @property (nonatomic,...) type *name;\n ...
    var headerInfo: [String: String] = [:]
    var messagesInfo: [String: String] = [:]
    
    private init() {}
    
    func removeAll() {
        classNames.removeAll()
        mappingTable.removeAll()
        headerInfo.removeAll()
        messagesInfo.removeAll()
        mappingKeywordsTable.removeAll()
    }
    
    func fileName(header: Bool = true) -> String {
        return self.rootClassName + (header ? ".h" : ".m")
    }
}

class PZParse {
    
    private let jsonInfo = PZJsonInfo.shared
    open let headerKey = "header"
    open let messagesKey = "messages"
    
    private func removeAll() {
        jsonInfo.removeAll()
    }
    
    func parse(_ jsonString: String, handle: @escaping (_ content:[String:String]?, _ error: Error?) -> () ) {
        runOnBackground {
            guard let data = jsonString.data(using: String.Encoding.utf8) else  {
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                // 清空之前的数据
                self.jsonInfo.removeAll()
                
                if  let object = json as? [String: Any] {
                    if  object.keys.count == 0 {
                        return
                    }
                    self.parse(json: JSON(object))
                }
                else if let object = json as? [Any],let first = object.first {
                    if  object.count == 0 {
                        return
                    }
                    self.parse(json: JSON(first))
                }
                
                let header = [self.makeupCopyrights(header: true),
                              self.makeupRefrence(header: true),
                              self.makeupImplicitState(),
                              self.makeupHeaderClasses()].reduce("", +)
                let messages = [self.makeupCopyrights(header: false),
                                self.makeupRefrence(header: false),
                                self.makeupMessagesClasses()].reduce("", +)
                
                self.runOnUiThread {
                    handle([self.headerKey: header,self.messagesKey: messages],nil)
                }
            } catch  {
                print(error.localizedDescription)
                self.runOnUiThread {
                    handle(nil,error)
                }
            }
        }
    }
    
    private func makeupCopyrights(header: Bool) -> String{
        var copyrights = "//\n//\t\(jsonInfo.fileName(header: header))\n"
        if let me = ABAddressBook.shared()?.me(){
            if let firstName = me.value(forProperty: kABFirstNameProperty as String) as? String{
                copyrights += "//\n//\tCreate by \(firstName)"
                if let lastName = me.value(forProperty: kABLastNameProperty as String) as? String{
                    copyrights += " \(lastName)"
                }
            }
            copyrights += " on \(getTodayFormattedDay())\n//\tCopyright © \(getYear())"
            if let organization = me.value(forProperty: kABOrganizationProperty as String) as? String{
                copyrights += " \(organization)"
            }
            copyrights += ". All rights reserved.\n//\n"
        }
        return copyrights
    }
    
    private func makeupRefrence(header: Bool) -> String {
        return header == true ? "\n#import <UIKit/UIKit.h>\n" : "\n#import \"\(self.jsonInfo.rootClassName).h\"\n"
    }
    
    private func makeupImplicitState() -> String {
        guard jsonInfo.classNames.count > 1 else {
            return ""
        }
        var implicitState = jsonInfo.classNames.reversed()
            .filter { (key) -> Bool in
                return key != jsonInfo.rootClassName
            }.map({ (key) -> String in
                return (jsonInfo.classPrefix ?? "") + key.capitalizingFirstLetter() + ","
            })
            .reduce("\n@class ", +)
        let range: Range = implicitState.index(implicitState.endIndex, offsetBy: -1) ..< implicitState.endIndex
        implicitState.replaceSubrange(range, with: ";\n")
        return implicitState
    }
    
    private func makeupHeaderClasses() -> String {
        var tmpString = ""
        for className in jsonInfo.classNames.reversed() {
            let prefix = className != jsonInfo.rootClassName ? (jsonInfo.classPrefix ?? "") : ""
            tmpString.append("\n@interface \(prefix + className.capitalizingFirstLetter()) : NSObject \n\n")
            if  let value = jsonInfo.headerInfo[className] {
                tmpString.append(value)
            }
            tmpString.append("\n@end\n")
        }
        return tmpString
    }
    
    private func makeupMessagesClasses() -> String {
        var tmpString = ""
        for className in jsonInfo.classNames.reversed() {
            let prefix = jsonInfo.classPrefix ?? ""
            if className ==  jsonInfo.rootClassName {
                 tmpString.append("\n@implementation \(className.capitalizingFirstLetter())\n")
            } else {
                 tmpString.append("\n@implementation \(prefix + className.capitalizingFirstLetter())\n")
            }
            if let mappingClassArray = jsonInfo.mappingTable[className] {
                tmpString.append("\n+ (NSDictionary *)mj_objectClassInArray {\n \treturn @{\(mappingClassArray.map{$0+","}.reduce("", +))};\n}\n")
            }
            if let mappingKeywords = jsonInfo.mappingKeywordsTable[className] {
                tmpString.append("\n+ (NSDictionary *)mj_replacedKeyFromPropertyName {\n \treturn @{\(mappingKeywords.map{$0+","}.reduce("", +))};\n}\n")
            }
            tmpString.append("\n@end\n")
            
            print(tmpString)
        
        }
        
        return tmpString
    }
}

// MARK: - parse
fileprivate extension PZParse {
    
    
    
    // 其中 json: JSON 是字典
    func parse(_ className: String? = nil, json: JSON) {
        let shared = PZJsonInfo.shared
        var tmpClassName = shared.rootClassName
        if  let tmpName = className {
            if  tmpName.count != 0 {
                tmpClassName = tmpName
            }
        }
        
    
        var headerInfoString = ""
        for (name,subJson):(String, JSON) in json {
            
            var qualifier = ""
            var type = ""
            if  name == "id" {
                print(name)
            }
            
            var key = name
            
            if subJson.type == .array{
                //如果是数组类名去掉复数
                //tmpClassName = pluralize(tmpClassName)
                key = singularize(key)
            }
            
            if  check(name) == true {
                key += KEYWORDSUFFIX
                if jsonInfo.mappingKeywordsTable[tmpClassName] == nil {
                    jsonInfo.mappingKeywordsTable[tmpClassName] = ["@\"\(key)\":@\"\(name)\""]
                } else {
                    jsonInfo.mappingKeywordsTable[tmpClassName]?.append("@\"\(key)\":@\"\(name)\"")
                }
            }
            
            switch subJson.type {
            case .array:
                qualifier = "strong"
                let first = subJson.arrayValue.first
                if  first?.type == .dictionary {
                    type = "NSArray <\(jsonInfo.classPrefix ?? "")\(key.capitalizingFirstLetter()) *> *"
                  
                    
                    if jsonInfo.mappingTable[tmpClassName] == nil {
                        jsonInfo.mappingTable[tmpClassName] = ["@\"\(name)\":[\(jsonInfo.classPrefix ?? "")\(key.capitalizingFirstLetter()) class]\n"]
                    } else {
                        jsonInfo.mappingTable[tmpClassName]?.append("@\"\(name)\":[\(jsonInfo.classPrefix ?? "")\(key.capitalizingFirstLetter()) class]\n")
                    }
                    
                    
                    
                    self.parse(key, json: first!)
                } else if first?.type == .string {
                    type = "NSArray <NSString *> *"
                } else if first?.type == .number {
                    type = "NSArray <NSNumber *> *"
                } else {
                    type = "NSArray *"
                }
            case .dictionary:
                qualifier = "strong"
                type = "\(jsonInfo.classPrefix ?? "")\(key.capitalizingFirstLetter()) *"
                self.parse(key, json: subJson)
            case .string:
                qualifier = "copy"
                type = "NSString *"
            case .number:
                qualifier = "assign"
                let tmpNumber:NSNumber = subJson.numberValue
                if  String(cString: tmpNumber.objCType) == "d" ||
                    String(cString: tmpNumber.objCType) == "f" {
                    type = "CGFloat"
                } else {
                    type = "NSInteger"
                }
            case .bool:
                qualifier = "assign"
                type = "BOOL"
            default:
                qualifier = "strong"
                type = "NSObject *"
            }
            
            if  subJson.type  == .array {
                headerInfoString.append("@property (nonatomic, \(qualifier)) \(type) \(name);\n")
            }else{
                headerInfoString.append("@property (nonatomic, \(qualifier)) \(type) \(key);\n")
            }
        }
        shared.headerInfo[tmpClassName] = headerInfoString
        if  shared.classNames.contains(tmpClassName) == false {
            shared.classNames.append(tmpClassName)
        }
    }
    
    func formatArrayClassName(_ name: String) -> String {
        var myString = name
        if myString.hasSuffix("s") || myString.hasSuffix("es") {
            myString = String(myString.dropLast())
            if myString.hasSuffix("e") {
                myString = String(myString.dropLast())
            }
        }
        return myString
    }
    
    
    /*
     根据名词复数变化规则
     1.一般情况加s。
     2.以s，x，sh，ch结尾加es，读/iz/。
     3.以辅音字母+y结尾，变y为i再加es，读/iz/。
     4.以y结尾的专有名词或元音字母+y结尾的名词变复数时，直接加s，读/z/。
     6.以f，fe结尾，去f，fe变ves。
     */
    
   
    
//
//    func pluralize(_ word: String) -> String {
//        // 判断是否以 s, x, sh, ch 结尾，如果是，加 es
//        if word.hasSuffix("s") || word.hasSuffix("x") || word.hasSuffix("sh") || word.hasSuffix("ch") {
//            return word + "es"
//        }
//        // 判断是否以辅音字母 + y 结尾，如果是，变 y 为 i，再加 es
//        if word.hasSuffix("y") && !word.hasSuffix("ay") && !word.hasSuffix("ey") && !word.hasSuffix("iy") && !word.hasSuffix("oy") && !word.hasSuffix("uy") {
//            let index = word.index(word.endIndex, offsetBy: -1)
//            let beforeY = word[..<index]
//            let lastChar = String(beforeY.last!)
//            if !lastChar.isVowel {
//                return beforeY + "ies"
//            } else {
//                return beforeY + "s"
//            }
//        }
//        // 判断是否以 o 结尾，如果是，有些加 s，有些加 es
//        if word.hasSuffix("o") {
//            let index = word.index(word.endIndex, offsetBy: -1)
//            let secondLastChar = word[index]
//            if String(secondLastChar).rangeOfCharacter(from: .vowels) == nil {
//                return word + "es"
//            } else {
//                return word + "s"
//            }
//        }
//        // 判断是否以 f 或 fe 结尾，如果是，去掉 f 或 fe，加 ves
//        if word.hasSuffix("f") {
//            let index = word.index(word.endIndex, offsetBy: -1)
//            let beforeF = word[..<index]
//            return beforeF + "ves"
//        }
//        if word.hasSuffix("fe") {
//            let index = word.index(word.endIndex, offsetBy: -2)
//            let beforeFe = word[..<index]
//            return beforeFe + "ves"
//        }
//        // 其他情况，直接加 s
//        return word + "s"
//    }
//
    func singularize(_ word: String) -> String {
        //两个字母的不判断
        if(word.count < 3){
            return word
        }
        
        
     //   let vowels: CharacterSet = .init(charactersIn: "aeiouAEIOU")
        
        // 判断是否以 s, x, sh, ch 结尾，如果是，去掉 es
        if word.hasSuffix("ses") || word.hasSuffix("xes")  ||  word.hasSuffix("shes") || word.hasSuffix("ches") {
            let index = word.index(word.endIndex, offsetBy: -2)
            return String(word[..<index])
        }
        // 判断是否以辅音字母 + y 结尾，如果是，变 y 为 i，再加 es
        if word.hasSuffix("ies") && !word.hasSuffix("aies") && !word.hasSuffix("eies") && !word.hasSuffix("iies") && !word.hasSuffix("oies") && !word.hasSuffix("uies") {
            let index = word.index(word.endIndex, offsetBy: -3)
            let beforeIes = word[..<index]
            let lastChar = String(beforeIes.last!)
            if !lastChar.isVowel {
                return beforeIes + "y"
            } else {
                return beforeIes + "s"
            }
        }
        // 判断是否以 ves 结尾，如果是，去掉 ves，加 f 或 fe
        if word.hasSuffix("ves") {
            let index = word.index(word.endIndex, offsetBy: -3)
            let beforeVes = word[..<index]
            let lastTwoChars = word[index...]
            if lastTwoChars == "ves" && beforeVes.hasSuffix("f") {
                let index = beforeVes.index(beforeVes.endIndex, offsetBy: -1)
                return beforeVes[..<index] + "fe"
            } else {
                return beforeVes + "f"
            }
        }
        // 其他情况，直接去掉 s
        if word.hasSuffix("s") {
            let index = word.index(word.endIndex, offsetBy: -1)
            return String(word[..<index])
        }
        // 否则返回原字符串
        return word
    }
    
    /// 检测属性名是否包含关键字
    func check(_ property: String) -> Bool{
        var tmpString = false
        for keyword in KEYWORDS {
            if  keyword == property {
                tmpString = true
                break
            }
        }
        return tmpString
    }
}

// MARK: - From JSONExport: https://github.com/Ahmed-Ali/JSONExport
fileprivate extension PZParse {
    /**
     Returns the current year as String
     */
    func getYear() -> String
    {
        return "\((Calendar.current as NSCalendar).component(.year, from: Date()))"
    }
    
    /**
     Returns today date in the format dd/mm/yyyy
     */
    func getTodayFormattedDay() -> String
    {
        let components = (Calendar.current as NSCalendar).components([.day, .month, .year], from: Date())
        return "\(components.day!)/\(components.month!)/\(components.year!)"
    }
    
    func runOnBackground(_ task: @escaping () -> Void) {
        DispatchQueue.global(qos: DispatchQoS.QoSClass.default).async {
            task();
        }
    }
    
    func runOnUiThread(_ task: @escaping () -> Void) {
        DispatchQueue.main.async(execute: { () -> Void in
            task();
        })
    }
}

fileprivate extension String {
    // from : https://stackoverflow.com/a/26306372
    func capitalizingFirstLetter() -> String {
        return prefix(1).uppercased() + dropFirst()
    }
    

    
    mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
}


extension Character {
    var isVowel: Bool {
        return "aeiouAEIOU".contains(self)
    }
}
//
extension String {
 

    var isVowel: Bool {
        return "aeiouAEIOU".contains(self)
    }


}
