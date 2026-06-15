import os
import wave
import struct
import math

os.makedirs('assets/sounds', exist_ok=True)

def generate_beep(filename, freq, duration_sec, sample_rate=44100):
    num_samples = int(sample_rate * duration_sec)
    with wave.open(filename, 'w') as w:
        w.setnchannels(1) # mono
        w.setsampwidth(2) # 2 bytes
        w.setframerate(sample_rate)
        
        for i in range(num_samples):
            # smooth envelope to avoid clicking
            envelope = 1.0
            if i < 400: envelope = i / 400.0
            elif i > num_samples - 400: envelope = (num_samples - i) / 400.0
            
            value = int(envelope * 32767.0 * math.sin(2.0 * math.pi * freq * (i / sample_rate)))
            data = struct.pack('<h', value)
            w.writeframesraw(data)

# Join sound: a pleasant two-tone or just a higher beep
generate_beep('assets/sounds/join.wav', 600, 0.2)
generate_beep('assets/sounds/notification.wav', 400, 0.3)
print("Generated local wav files.")
