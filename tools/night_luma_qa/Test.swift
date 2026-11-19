private let p = NightLumaPolicy()
for _ in 0..<3 { p.observe(mean:0.50,darkFraction:0.2,low:0.15,high:0.85) }
precondition(!p.active)
for _ in 0..<2 { p.observe(mean:0.07,darkFraction:0.95,low:0.01,high:0.22) }
precondition(!p.active)
p.observe(mean:0.07,darkFraction:0.95,low:0.01,high:0.22)
precondition(p.active)
precondition(p.nextStrengthStep()==1)
for _ in 0..<15 { _=p.nextStrengthStep() }
precondition(p.nextStrengthStep()==16)
p.observe(mean:0.50,darkFraction:0.2,low:0.15,high:0.85)
precondition(!p.active && p.nextStrengthStep()==0)
for _ in 0..<3 { p.observe(mean:0.008,darkFraction:1,low:0.001,high:0.019) }
precondition(!p.active)
for _ in 0..<3 { p.observe(mean:0.012,darkFraction:1,low:0,high:0.055) }
precondition(p.active)
for _ in 0..<16 { _=p.nextStrengthStep() }
precondition((1...15).contains(p.nextStrengthStep()))
p.reset()
for _ in 0..<3 { p.observe(mean:0.10,darkFraction:0.92,low:0.03,high:0.25) }
precondition(p.active)
p.observe(mean:0.36,darkFraction:0.55,low:0.1,high:0.7); precondition(p.active)
p.observe(mean:0.36,darkFraction:0.55,low:0.1,high:0.7); precondition(!p.active)
var histogram=[Int](repeating:0,count:256);histogram[20]=100;histogram[80]=92
precondition(NightLumaPolicy.percentile(histogram,count:192,percentile:10)==20)
precondition(NightLumaPolicy.percentile(histogram,count:192,percentile:95)==80)
for (lo,hi) in [(0,255),(16,235)] { for step in 0...16 {
    let table=NightLumaPolicy.lut(step:step,low:lo,high:hi).map(Int.init)
    precondition(zip(table,table.dropFirst()).allSatisfy { $0 <= $1 })
    precondition(table.indices.allSatisfy { table[$0] >= $0 })
    precondition(table[lo]==lo && table[hi]==hi)
    if step==0 { precondition(table==Array(0...255)) }
    print(table.map(String.init).joined(separator:","))
}}
