package com.mingyu.kyeobom

fun main() {
    val p = NightLumaPolicy()
    repeat(3) { p.observe(.50,.2,.15,.85) }; check(!p.active)
    repeat(2) { p.observe(.07,.95,.01,.22) }; check(!p.active)
    p.observe(.07,.95,.01,.22); check(p.active)
    check(p.nextStrengthStep()==1); repeat(15) { p.nextStrengthStep() }
    check(p.nextStrengthStep()==16)
    p.observe(.50,.2,.15,.85); check(!p.active && p.nextStrengthStep()==0)
    repeat(3) { p.observe(.008,1.0,.001,.019) }; check(!p.active)
    repeat(3) { p.observe(.012,1.0,0.0,.055) }; check(p.active)
    repeat(16) { p.nextStrengthStep() }; check(p.nextStrengthStep() in 1..15)
    p.reset(); repeat(3) { p.observe(.10,.92,.03,.25) }; check(p.active)
    p.observe(.36,.55,.1,.7); check(p.active)
    p.observe(.36,.55,.1,.7); check(!p.active)
    val histogram = IntArray(256); histogram[20]=100; histogram[80]=92
    check(NightLumaPolicy.percentile(histogram,192,10)==20)
    check(NightLumaPolicy.percentile(histogram,192,95)==80)
    for ((lo,hi) in listOf(0 to 255,16 to 235)) for (step in 0..16) {
        val table = NightLumaPolicy.lut(step,lo,hi).map { it.toInt() and 255 }
        check(table.zipWithNext().all { (a,b) -> a<=b })
        check(table.indices.all { table[it]>=it })
        check(table[lo]==lo && table[hi]==hi)
        if(step==0)check(table==(0..255).toList())
        println(table.joinToString(","))
    }
}
