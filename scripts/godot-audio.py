"""Small original synthetic office sounds (16kHz mono PCM, no external assets)."""
from pathlib import Path
import math, random, struct, wave
root=Path('godot/assets/audio'); root.mkdir(parents=True,exist_ok=True)
rate=16000
def write(name,seconds,signal):
    with wave.open(str(root/(name+'.wav')),'wb') as file:
        file.setparams((1,2,rate,0,'NONE','not compressed'))
        file.writeframes(b''.join(struct.pack('<h',round(max(-1,min(1,signal(i/rate)))*32767)) for i in range(int(seconds*rate))))
# Integer frequencies make the hum loop seamless. The quieter noise bed is periodic.
rng=random.Random(71); phases=[rng.random()*math.tau for _ in range(12)]
write('ventilation',4,lambda t: .14*math.sin(math.tau*96*t)+sum(.017*math.sin(math.tau*(171+i*59)*t+phases[i]) for i in range(12)))
write('server-fan',4,lambda t: .13*math.sin(math.tau*180*t)+sum(.018*math.sin(math.tau*(289+i*71)*t+phases[i]) for i in range(12)))
write('interaction',.09,lambda t: .18*math.sin(math.tau*740*t)*math.sin(math.pi*t/.09)**2)
write('door-latch',.35,lambda t: (.13*math.sin(math.tau*155*t)+.07*math.sin(math.tau*920*t))*math.exp(-t*18))
