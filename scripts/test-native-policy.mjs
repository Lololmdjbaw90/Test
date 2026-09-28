// Runs the actual Swift policy with the same fixtures, on the macOS CI runner.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
const source=fs.readFileSync('native/Sugerly/Firebase/ContentGate.swift','utf8').split('actor ContentGate')[0]
 .replace('Bundle.main.url(forResource: "moderationLexicon", withExtension: "json")','Optional(URL(fileURLWithPath: CommandLine.arguments[1]))');
const stub=`import Foundation\ntypealias Doc = [String:Any]\nextension Dictionary where Key == String, Value == Any { func str(_ key:String)->String { self[key] as? String ?? "" } }\n`;
const test=`
let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
let cases = try JSONSerialization.jsonObject(with: bytes) as! [Doc]
for item in cases {
 let verdict = ContentPolicy.analyze(item.str("text"), field: item.str("field"))
 precondition(verdict.reason.isEmpty == (item["safe"] as! Bool), "Unexpected native decision: \\(item.str("text"))")
 precondition(verdict.review == (item["review"] as? Bool ?? false), "Unexpected native review: \\(item.str("text"))")
}
print("PASS \\(cases.count) shared Swift policy fixtures")
`;
const dir=fs.mkdtempSync(path.join(os.tmpdir(),'sugerly-policy-'));
const file=path.join(dir,'Policy.swift');fs.writeFileSync(file,stub+source+test);
execFileSync('swift',[file,path.resolve('src/lib/moderationLexicon.json'),path.resolve('scripts/moderation-cases.json')],{stdio:'inherit'});
