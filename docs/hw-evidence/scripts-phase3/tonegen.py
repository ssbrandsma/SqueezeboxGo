import wave, struct, math
N=44100*3; F=440.0; AMP=0.1  # 3s, 440Hz, -20dBFS amplitude
w=wave.open('/tmp/tone3s.wav','wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(44100)
for i in range(N):
    v=int(AMP*32767*math.sin(2*math.pi*F*i/44100))
    w.writeframes(struct.pack('<hh',v,v))
w.close(); print("WROTE /tmp/tone3s.wav")
