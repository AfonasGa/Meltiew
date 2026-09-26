"""A small offline synthesizer for Meltopia's music and sound effects.

Everything is numpy: oscillators, envelopes, a Karplus-Strong pluck, an FM electric
piano, detuned saw pads, drums from noise and sine sweeps, IIR filters, a Freeverb
style reverb and a soft limiter. Loops are rendered twice and the second pass is
kept, so reverb tails and echoes wrap around and the loop point is seamless.
"""
import numpy as np
from scipy.signal import lfilter, butter, sosfilt

SR = 44100
RNG = np.random.default_rng(7)

NOTE_NAMES = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
              "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(name):
    """'A4' -> 69, 'Eb3' -> 51."""
    head = name[:-1]
    return NOTE_NAMES[head] + 12 * (int(name[-1]) + 1)


def hz(n):
    if isinstance(n, str):
        n = midi(n)
    return 440.0 * 2 ** ((n - 69) / 12)


def t_of(n):
    return np.arange(int(n)) / SR


# --- oscillators ---------------------------------------------------------------------

def sine(f, n, phase=0.0):
    return np.sin(2 * np.pi * f * t_of(n) + phase)


def saw(f, n, harmonics=None):
    """Band-limited saw (additive), bright but alias-free."""
    t = t_of(n)
    top = harmonics or max(1, int(min(40, (SR / 2.2) / f)))
    out = np.zeros(len(t))
    for k in range(1, top + 1):
        out += np.sin(2 * np.pi * f * k * t) / k
    return out * (2 / np.pi)


def square(f, n):
    t = t_of(n)
    top = max(1, int(min(31, (SR / 2.2) / f)))
    out = np.zeros(len(t))
    for k in range(1, top + 1, 2):
        out += np.sin(2 * np.pi * f * k * t) / k
    return out * (4 / np.pi)


def tri(f, n):
    t = t_of(n)
    out = np.zeros(len(t))
    for i, k in enumerate(range(1, 16, 2)):
        out += ((-1) ** i) * np.sin(2 * np.pi * f * k * t) / (k * k)
    return out * (8 / np.pi ** 2)


def noise(n):
    return RNG.uniform(-1, 1, int(n))


# --- envelopes and filters ---------------------------------------------------------------

def adsr(n, a=0.01, d=0.1, s=0.7, r=0.2, hold=None):
    """Attack/decay/sustain for `hold` seconds (default: the note fills n), then release."""
    n = int(n)
    env = np.zeros(n)
    A, D, R = int(a * SR), int(d * SR), int(r * SR)
    H = n - R if hold is None else int(hold * SR)
    H = max(H, 1)
    i = 0
    seg = min(A, H)
    env[:seg] = np.linspace(0, 1, seg, endpoint=False) if seg else 0
    i = seg
    seg = min(D, max(0, H - i))
    env[i:i + seg] = np.linspace(1, s, seg, endpoint=False)
    i += seg
    if H > i:
        env[i:H] = s
    last = env[H - 1] if H > 0 else 0
    tail = min(R, n - H)
    if tail > 0:
        env[H:H + tail] = np.linspace(last, 0, tail)
    return env


def exp_decay(n, tau):
    return np.exp(-t_of(n) / tau)


def lowpass(x, cutoff, order=2):
    sos = butter(order, min(cutoff, SR / 2.1), 'low', fs=SR, output='sos')
    return sosfilt(sos, x)


def highpass(x, cutoff, order=2):
    sos = butter(order, cutoff, 'high', fs=SR, output='sos')
    return sosfilt(sos, x)


def bandpass(x, lo, hi, order=2):
    sos = butter(order, [lo, min(hi, SR / 2.1)], 'band', fs=SR, output='sos')
    return sosfilt(sos, x)


def sweep_lowpass(x, start, end, block=512):
    """A lowpass whose cutoff glides from start to end (log), filtered in blocks."""
    out = np.zeros_like(x)
    zi = None
    n = len(x)
    for i in range(0, n, block):
        frac = i / max(1, n - 1)
        fc = start * (end / start) ** frac
        sos = butter(2, min(fc, SR / 2.1), 'low', fs=SR, output='sos')
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        out[i:i + block], zi = sosfilt(sos, x[i:i + block], zi=zi)
    return out


def drive(x, amount=2.0):
    return np.tanh(x * amount) / np.tanh(amount)


# --- instruments --------------------------------------------------------------------

def ep(note, dur, vel=0.8):
    """Electric piano: FM tine (1:1 with a 14:1 click) over a sine body, gentle tremolo."""
    f = hz(note)
    n = int((dur + 1.2) * SR)
    t = t_of(n)
    idx = 1.6 * np.exp(-t / 0.35) + 0.25
    mod = np.sin(2 * np.pi * f * t) * idx
    body = np.sin(2 * np.pi * f * t + mod)
    click = np.sin(2 * np.pi * f * 14 * t) * np.exp(-t / 0.012) * 0.25
    tone = body * 0.8 + 0.2 * np.sin(4 * np.pi * f * t) * np.exp(-t / 0.5) + click
    env = adsr(n, 0.004, 1.2, 0.35, 0.5, hold=dur) * (0.85 + 0.15 * np.sin(2 * np.pi * 4.5 * t))
    return tone * env * vel


def pluck(note, dur, vel=0.7, bright=0.5, decay=0.996):
    """Karplus-Strong string: a burst of filtered noise ringing in a delay line."""
    f = hz(note)
    N = max(2, int(SR / f))
    n = int((dur + 0.8) * SR)
    burst = np.zeros(n)
    exc = lowpass(noise(N), 1500 + 6000 * bright)
    burst[:N] = exc
    # y[n] = x[n] + c * (y[n-N] + y[n-N-1]), a delay-line block at a time.
    c = 0.5 * decay
    y = np.zeros(n + N + 1)
    xx = np.concatenate([np.zeros(N + 1), burst])
    for i in range(N + 1, n + N + 1, N):
        m = min(N, n + N + 1 - i)
        y[i:i + m] = xx[i:i + m] + c * (y[i - N:i - N + m] + y[i - N - 1:i - N - 1 + m])
    y = y[N + 1:]
    env = adsr(n, 0.001, 0.05, 1.0, 0.25, hold=dur + 0.5)
    return y * env * vel * 1.4


def pad(notes, dur, vel=0.4, cutoff=1400, attack=1.2, release=1.6, voices=3, detune=0.08):
    """Warm pad: a few detuned saws per note, lowpassed, slow in and out."""
    n = int((dur + release) * SR)
    out = np.zeros(n)
    for nt in notes:
        f = hz(nt)
        for v in range(voices):
            cents = (v - (voices - 1) / 2) * detune * 100
            out += saw(f * 2 ** (cents / 1200), n, harmonics=18)
    out = lowpass(out, cutoff, 2)
    env = adsr(n, attack, 0.5, 0.85, release, hold=dur)
    return out * env * vel / (len(notes) * voices) * 2.2


def bell(note, dur, vel=0.5):
    """Music-box bell: inharmonic sines that die away."""
    f = hz(note)
    n = int((dur + 2.5) * SR)
    t = t_of(n)
    out = (np.sin(2 * np.pi * f * t) * np.exp(-t / 1.4)
           + 0.5 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t / 0.6)
           + 0.25 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t / 0.25)
           + 0.12 * np.sin(2 * np.pi * f * 8.9 * t) * np.exp(-t / 0.1))
    return out * adsr(n, 0.002, 0.1, 1.0, 0.1) * vel * 0.6


def sub_bass(note, dur, vel=0.8, glide_from=None):
    f = hz(note)
    n = int((dur + 0.15) * SR)
    t = t_of(n)
    if glide_from is not None:
        f0 = hz(glide_from)
        freq = f + (f0 - f) * np.exp(-t / 0.03)
        ph = 2 * np.pi * np.cumsum(freq) / SR
    else:
        ph = 2 * np.pi * f * t
    tone = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    return tone * adsr(n, 0.008, 0.2, 0.8, 0.12, hold=dur) * vel


def reese(note, dur, vel=0.8, cutoff=900, dist=3.0):
    """Gritty chase bass: two detuned saws, a sub, filtered and driven."""
    f = hz(note)
    n = int((dur + 0.08) * SR)
    x = saw(f * 1.007, n, 24) + saw(f * 0.993, n, 24) + 0.8 * np.sin(2 * np.pi * f / 2 * t_of(n))
    x = lowpass(x, cutoff, 2)
    x = drive(x * 0.6, dist)
    return x * adsr(n, 0.003, 0.08, 0.75, 0.05, hold=dur) * vel


def brass_stab(notes, dur, vel=0.6):
    n = int((dur + 0.4) * SR)
    x = np.zeros(n)
    for nt in notes:
        f = hz(nt)
        x += saw(f, n, 30) + 0.6 * saw(f * 1.004, n, 30)
    x = sweep_lowpass(x, 5000, 700)
    return drive(x / len(notes) * 0.5, 1.8) * adsr(n, 0.01, 0.25, 0.45, 0.3, hold=dur) * vel


def lead(note, dur, vel=0.5, vibrato=5.5):
    f = hz(note)
    n = int((dur + 0.3) * SR)
    t = t_of(n)
    vib = 1 + 0.006 * np.sin(2 * np.pi * vibrato * t) * np.clip(t / 0.3, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    x = np.zeros(n)
    for k in range(1, 14):
        x += np.sin(ph * k) / k * (0.9 ** k)
    x = lowpass(x, 3200)
    return x * adsr(n, 0.04, 0.2, 0.75, 0.25, hold=dur) * vel * 0.6


# --- drums ----------------------------------------------------------------------------

def kick(vel=1.0, punch=1.0, length=0.45):
    n = int(length * SR)
    t = t_of(n)
    f = 45 + 130 * np.exp(-t / (0.03 * punch))
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / 0.18)
    click = lowpass(noise(n), 3000) * np.exp(-t / 0.004) * 0.4
    return drive((body + click) * vel, 1.3)


def snare(vel=0.8, tone=190, length=0.3, snappy=0.7):
    n = int(length * SR)
    t = t_of(n)
    body = np.sin(2 * np.pi * tone * t) * np.exp(-t / 0.06)
    nz = bandpass(noise(n), 1200, 9000) * np.exp(-t / 0.09) * snappy
    return (body * 0.6 + nz) * vel


def clap(vel=0.7):
    n = int(0.35 * SR)
    t = t_of(n)
    nz = bandpass(noise(n), 900, 6000)
    env = np.zeros(n)
    for k, off in enumerate([0, 0.011, 0.022, 0.034]):
        i = int(off * SR)
        env[i:] += np.exp(-(t[: n - i]) / (0.008 if k < 3 else 0.12))
    return nz * env * vel * 0.5


def hat(vel=0.35, open_=False):
    n = int((0.35 if open_ else 0.06) * SR)
    t = t_of(n)
    nz = highpass(noise(n), 7000, 4)
    return nz * np.exp(-t / (0.12 if open_ else 0.018)) * vel


def shaker(vel=0.2):
    n = int(0.09 * SR)
    t = t_of(n)
    env = np.minimum(t / 0.02, 1) * np.exp(-t / 0.03)
    return bandpass(noise(n), 4000, 11000) * env * vel


def tom(note="D2", vel=0.8):
    n = int(0.5 * SR)
    t = t_of(n)
    f = hz(note) * (1 + 0.6 * np.exp(-t / 0.04))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t / 0.22) * vel


def impact(vel=1.0, length=3.0):
    """A cinematic boom: sub drop, noise burst, long tail."""
    n = int(length * SR)
    t = t_of(n)
    f = 30 + 70 * np.exp(-t / 0.12)
    ph = 2 * np.pi * np.cumsum(f) / SR
    boom = np.sin(ph) * np.exp(-t / 0.9)
    nz = lowpass(noise(n), 1800) * np.exp(-t / 0.35) * 0.5
    return drive((boom + nz) * vel, 1.6)


def riser(length=2.0, vel=0.4):
    n = int(length * SR)
    t = t_of(n)
    nz = noise(n)
    x = sweep_lowpass(nz, 300, 9000)
    return x * (t / length) ** 2 * vel


# --- mixing ---------------------------------------------------------------------------

class Track:
    """A stereo buffer you drop sounds into at beat positions."""

    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.buf = np.zeros((2, self.n))

    def add(self, x, at_sec, gain=1.0, pan=0.0, wrap=True):
        i = int(at_sec * SR)
        x = np.asarray(x) * gain
        l_g = np.cos((pan + 1) * np.pi / 4) * np.sqrt(2)
        r_g = np.sin((pan + 1) * np.pi / 4) * np.sqrt(2)
        end = i + len(x)
        if end <= self.n:
            self.buf[0, i:end] += x * l_g
            self.buf[1, i:end] += x * r_g
        else:
            k = self.n - i
            self.buf[0, i:] += x[:k] * l_g
            self.buf[1, i:] += x[:k] * r_g
            if wrap:
                rest = x[k:]
                while len(rest):
                    m = min(len(rest), self.n)
                    self.buf[0, :m] += rest[:m] * l_g
                    self.buf[1, :m] += rest[:m] * r_g
                    rest = rest[m:]

    def add_stereo(self, lr, at_sec=0.0, gain=1.0):
        for ch in (0, 1):
            self.add_mono_ch(lr[ch] * gain, at_sec, ch)

    def add_mono_ch(self, x, at_sec, ch):
        i = int(at_sec * SR)
        rest = x
        pos = i
        while len(rest):
            pos %= self.n
            m = min(len(rest), self.n - pos)
            self.buf[ch, pos:pos + m] += rest[:m]
            rest = rest[m:]
            pos += m


def comb_ir(x, delay, fb, damp):
    """Damped feedback comb (Freeverb): y[n] = w[n-D], w = x + fb * lowpass(y).
    Done a delay-length block at a time, so it's fast for long signals."""
    n = len(x)
    y = np.zeros(n + delay)
    prev_w = np.zeros(delay)
    zi = np.zeros(1)
    for i in range(0, n, delay):
        xb = x[i:i + delay]
        m = len(xb)
        yb = prev_w[:m]
        y[i:i + m] = yb
        lp, zi = lfilter([1 - damp], [1, -damp], yb, zi=zi)
        wb = xb + fb * lp
        prev_w = np.zeros(delay)
        prev_w[:m] = wb
    return y[:n]


def allpass(x, delay, g=0.5):
    """Schroeder allpass, a delay-length block at a time."""
    n = len(x)
    y = np.zeros(n)
    prev_v = np.zeros(delay)
    for i in range(0, n, delay):
        xb = x[i:i + delay]
        m = len(xb)
        vb = xb + g * prev_v[:m]
        y[i:i + m] = -g * vb + prev_v[:m]
        prev_v = np.zeros(delay)
        prev_v[:m] = vb
    return y


def reverb(stereo, size=0.84, damp=0.25, wet=0.3, predelay=0.02, loops=True):
    """Freeverb-style: 8 parallel damped combs and 4 allpasses per side. With `loops`,
    the signal is run twice around so the tail from the end rings into the start."""
    combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
    aps = [556, 441, 341, 225]
    out = np.zeros_like(stereo)
    n = stereo.shape[1]
    for ch in (0, 1):
        spread = 0 if ch == 0 else 23
        x = stereo[ch]
        if loops:
            x = np.concatenate([x, x])
        pd = int(predelay * SR)
        x = np.concatenate([np.zeros(pd), x])[: len(x)]
        acc = np.zeros(len(x))
        for c in combs:
            acc += comb_ir(x, c + spread, size, damp)
        for a in aps:
            acc = allpass(acc, a + spread)
        acc = acc[n:] if loops else acc
        out[ch] = acc * 0.015
    return stereo * (1 - wet * 0.5) + out * wet


def echo(stereo, delay_sec, feedback=0.35, wet=0.25, loops=True, pingpong=True):
    D = int(delay_sec * SR)
    n = stereo.shape[1]
    out = np.zeros_like(stereo)
    for ch in (0, 1):
        x = np.concatenate([stereo[ch], stereo[ch]]) if loops else stereo[ch]
        y = np.zeros(len(x))
        prev = np.zeros(D)
        for i in range(0, len(x), D):
            xb = x[i:i + D]
            m = len(xb)
            yb = prev[:m]
            y[i:i + m] = yb
            nxt = np.zeros(D)
            nxt[:m] = xb + feedback * yb
            prev = nxt
        y = lowpass(y, 5000)
        out[ch] = y[n:] if loops else y
    if pingpong:
        out = out[::-1] * 0.9 + out * 0.1
    return stereo + out * wet


def sidechain(stereo, beat_sec, depth=0.5, release=0.18, offset=0.0):
    n = stereo.shape[1]
    t = (t_of(n) - offset) % beat_sec
    # A few ms of attack so the duck never clicks (and the loop point stays smooth).
    env = 1 - depth * (1 - np.exp(-t / 0.006)) * np.exp(-t / release)
    return stereo * env


def master(stereo, target=0.9, drive_amt=1.4):
    x = stereo - stereo.mean(axis=1, keepdims=True)
    x = x / (np.abs(x).max() + 1e-9)
    x = np.tanh(x * drive_amt) / np.tanh(drive_amt)
    return x / (np.abs(x).max() + 1e-9) * target


def fade_edges(x, ms=4):
    n = int(ms / 1000 * SR)
    if x.ndim == 1:
        x[:n] *= np.linspace(0, 1, n)
        x[-n:] *= np.linspace(1, 0, n)
    else:
        x[:, :n] *= np.linspace(0, 1, n)
        x[:, -n:] *= np.linspace(1, 0, n)
    return x


def save(path, stereo, quality=0.55):
    """OGG Vorbis, written in small blocks (big single writes crash libsndfile's encoder)."""
    import soundfile as sf
    data = (stereo.T if stereo.ndim == 2 else stereo).astype(np.float32)
    channels = 1 if data.ndim == 1 else data.shape[1]
    with sf.SoundFile(path, 'w', SR, channels, format='OGG', subtype='VORBIS', compression_level=1 - quality) as f:
        for i in range(0, len(data), 4096):
            f.write(data[i:i + 4096])
