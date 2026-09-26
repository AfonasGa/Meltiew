"""Meltopia soundtrack and sound effects, written as code.

    python3 compose.py            # writes ../assets/*.ogg

lobby.ogg   "Porch Lights"  88 BPM lo-fi: electric piano, plucks, a hummable bell tune
calm.ogg    "Nightfall"     dark ambient for rounds while the killer is far away
chase.ogg   "Run"           150 BPM, the killer is close: drums, gritty bass, brass
sfx_*.ogg   generator, hits, spike, round start and endings
"""
import os
import numpy as np
import synth as S
from synth import hz, SR

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets')
os.makedirs(OUT, exist_ok=True)


def loop_hz(f, seconds):
    """A frequency with a whole number of cycles in the loop, so drones join seamlessly."""
    return round(f * seconds) / seconds


def swing_time(beat, bar, spb, swing=0.58):
    """Beat position (in beats, 16ths allowed) -> seconds, with 16th swing."""
    whole = int(beat * 4)
    frac = beat * 4 - whole
    t16 = whole
    if whole % 2 == 1:
        t16 = whole - 1 + 2 * swing
    return (bar * 4 + (t16 + frac) / 4) * spb


# ======================================================================================
# LOBBY: "Porch Lights"
# ======================================================================================

def lobby():
    bpm = 88
    spb = 60 / bpm
    bars = 24
    L = bars * 4 * spb
    music = S.Track(L)
    keys = S.Track(L)
    drums = S.Track(L)
    plk = S.Track(L)
    mel = S.Track(L)

    prog = [
        ("G2", ["B3", "D4", "F#4", "A4"]),    # Gmaj9
        ("F#2", ["A3", "C#4", "E4", "G#4"]),  # F#m9
        ("E2", ["G3", "B3", "D4", "F#4"]),    # Em9
        ("A2", ["G3", "C#4", "E4", "F#4"]),   # A13
    ]
    # Sections: 0-3 intro, 4-11 A, 12-19 B (tune), 20-23 thin outro back into the intro.
    for bar in range(bars):
        root, chord = prog[bar % 4]
        intro = bar < 4
        outro = bar >= 20
        # Electric piano comping: on 1, the "and" of 2 and a soft push before 4.
        hits = [(0, 1.3, 0.75), (1.5, 0.9, 0.5), (3.25, 0.7, 0.35)] if not intro else [(0, 3.8, 0.7)]
        for beat, dur, vel in hits:
            for j, nt in enumerate(chord):
                strum = j * 0.012
                keys.add(S.ep(nt, dur * spb, vel * (0.9 + 0.2 * S.RNG.random())), swing_time(beat, bar, spb) + strum,
                         gain=0.22, pan=-0.25 + j * 0.15)
        # A soft pad glues it together.
        music.add(S.pad(chord, 4 * spb, 0.5, cutoff=1300, attack=0.9, release=1.2), bar * 4 * spb, gain=0.33)
        if not intro:
            # Bass: root, then fifth or octave, walking into the next chord.
            nxt = prog[(bar + 1) % 4][0]
            r = S.midi(root)
            music.add(S.sub_bass(r, 1.4 * spb, 0.8), swing_time(0, bar, spb), gain=0.45)
            music.add(S.sub_bass(r + 7, 0.5 * spb, 0.6), swing_time(1.5, bar, spb), gain=0.5)
            music.add(S.sub_bass(r + 12, 0.6 * spb, 0.55), swing_time(2.5, bar, spb), gain=0.45)
            step = S.midi(nxt) + (1 if S.midi(nxt) < r else -1)
            music.add(S.sub_bass(step, 0.4 * spb, 0.5), swing_time(3.5, bar, spb), gain=0.45)
        # Drums: laid back, swung.
        if bar >= 2 and not (outro and bar >= 22):
            for b in (0, 1.75, 2.5):
                drums.add(S.kick(0.8, 0.9), swing_time(b, bar, spb), gain=0.5 if b == 0 else 0.35)
            for b in (1, 3):
                drums.add(S.snare(0.6, 210, snappy=0.5), swing_time(b, bar, spb), gain=0.3)
                drums.add(S.clap(0.4), swing_time(b, bar, spb) + 0.006, gain=0.15)
        if bar >= 1:
            for k in range(8):
                v = 0.25 + 0.1 * (k % 2 == 0) + 0.05 * S.RNG.random()
                drums.add(S.hat(v), swing_time(k * 0.5, bar, spb), gain=0.18, pan=0.3)
            for k in range(16):
                if k % 4 == 2:
                    drums.add(S.shaker(0.25), swing_time(k * 0.25, bar, spb), gain=0.16, pan=-0.35)
        # Pluck arpeggio through A and B.
        if 4 <= bar < 20:
            order = [0, 1, 2, 3, 2, 1, 3, 2]
            for k in range(8):
                nt = S.midi(chord[order[k]]) + (12 if k in (3, 6) else 0)
                plk.add(S.pluck(nt, 0.35 * spb, 0.5, bright=0.35), swing_time(k * 0.5, bar, spb), gain=0.13,
                        pan=0.45 if k % 2 else -0.45)

    # The tune (bell + soft lead), bars 12-19. (bar offset, beat, note, length in beats)
    tune = [
        (0, 0, "F#5", 0.5), (0, 0.5, "A5", 1), (0, 1.5, "B5", 1.5), (0, 3, "A5", 1),
        (1, 0, "E5", 0.5), (1, 0.5, "F#5", 0.5), (1, 1, "A5", 2), (1, 3.5, "F#5", 0.5),
        (2, 0, "D5", 0.5), (2, 0.5, "E5", 0.5), (2, 1, "F#5", 1), (2, 2, "B4", 2),
        (3, 0, "C#5", 0.5), (3, 0.5, "E5", 1), (3, 1.5, "A4", 2.5),
        (4, 0, "A5", 0.5), (4, 0.5, "B5", 1), (4, 1.5, "D6", 1.5), (4, 3, "B5", 1),
        (5, 0, "A5", 1), (5, 1, "F#5", 0.5), (5, 1.5, "E5", 1.5), (5, 3, "F#5", 1),
        (6, 0, "D5", 0.5), (6, 0.5, "E5", 1), (6, 1.5, "F#5", 0.5), (6, 2, "E5", 1), (6, 3, "D5", 1),
        (7, 0, "E5", 1), (7, 1, "C#5", 1), (7, 2, "A4", 2),
    ]
    for off, beat, nt, ln in tune:
        at = swing_time(beat, 12 + off, spb)
        mel.add(S.bell(nt, ln * spb, 0.55), at, gain=0.3, pan=0.15)
        mel.add(S.lead(nt, ln * spb * 0.9, 0.35), at, gain=0.14, pan=-0.1)

    # Vinyl: soft hiss and the odd crackle.
    n = music.n
    hiss = S.lowpass(S.noise(n), 5000) * 0.012
    crackle = np.zeros(n)
    for _ in range(int(L * 6)):
        i = S.RNG.integers(0, n - 200)
        crackle[i:i + 60] += S.RNG.uniform(-1, 1) * np.exp(-np.arange(60) / 8) * 0.25
    music.add(S.highpass(crackle, 1500) + hiss, 0, gain=0.8)

    wet_keys = S.reverb(keys.buf, 0.82, 0.3, 0.35)
    wet_plk = S.echo(plk.buf, 0.75 * spb, 0.38, 0.35)
    wet_plk = S.reverb(wet_plk, 0.8, 0.3, 0.3)
    wet_mel = S.echo(mel.buf, 0.75 * spb, 0.3, 0.25)
    wet_mel = S.reverb(wet_mel, 0.86, 0.25, 0.45)
    wet_drums = S.reverb(drums.buf, 0.7, 0.4, 0.15)
    mix = music.buf + wet_keys + wet_plk + wet_mel + wet_drums
    mix = S.sidechain(mix, spb, depth=0.18, release=0.2)
    mix = S.lowpass(mix, 11000)
    return S.master(mix, 0.85, 1.2)


# ======================================================================================
# CALM (round, killer far away): "Nightfall"
# ======================================================================================

def calm():
    bpm = 72
    spb = 60 / bpm
    bars = 16
    L = bars * 4 * spb
    base = S.Track(L)
    bells = S.Track(L)
    n = base.n
    t = np.arange(n) / SR
    # A low drone on D that breathes, joined exactly at the loop point.
    d1 = loop_hz(hz("D1"), L)
    a1 = loop_hz(hz("A1"), L)
    breath = 0.75 + 0.25 * np.sin(2 * np.pi * t / L * 4)
    drone = (np.sin(2 * np.pi * d1 * t) + 0.5 * np.sin(2 * np.pi * a1 * t) + 0.3 * np.sin(2 * np.pi * 2 * d1 * t + 0.4 * np.sin(2 * np.pi * t / L * 2)))
    base.add(drone * breath * 0.2, 0)
    # Dark pads, four bars each: Dm(add9), Bbmaj7, Gm9, A7sus(b9).
    chords = [["D3", "F3", "A3", "E4"], ["Bb2", "D3", "F3", "A3"], ["G2", "Bb2", "D3", "A3"], ["A2", "D3", "E3", "Bb3"]]
    for i, ch in enumerate(chords):
        base.add(S.pad(ch, 16 * spb, 0.55, cutoff=700, attack=3.0, release=4.0, detune=0.12), i * 16 * spb, gain=0.4)
    # A far-off heartbeat, slow.
    for bar in range(bars):
        for b in (0, 2):
            at = (bar * 4 + b) * spb
            base.add(S.kick(0.5, 1.6, 0.4), at, gain=0.22)
            base.add(S.kick(0.35, 1.6, 0.4), at + 0.24, gain=0.16)
    # Music box motif, sparse and sad, drifting between the speakers.
    motif = [(0, 0, "D5"), (0, 1.5, "F5"), (0, 3, "A5"), (1, 2, "E5"), (2, 0, "D5"), (2, 2, "Bb4"),
             (3, 0, "A4"), (3, 3, "C#5"), (8, 0, "F5"), (8, 1.5, "E5"), (8, 3, "D5"), (9, 2, "A4"),
             (10, 0, "Bb4"), (10, 2, "D5"), (11, 1, "E5"), (11, 3, "C#5")]
    for k, (bar, beat, nt) in enumerate(motif):
        bells.add(S.bell(nt, 2 * spb, 0.5), (bar * 4 + beat) * spb, gain=0.3, pan=-0.5 if k % 2 else 0.5)
    # Wind through the trees: noise through a slowly wandering band.
    wind = S.noise(n)
    out = np.zeros(n)
    blk = 2048
    for i in range(0, n, blk):
        c = 480 + 250 * np.sin(2 * np.pi * (i / SR) / 7.3) + 110 * np.sin(2 * np.pi * (i / SR) / 3.1)
        out[i:i + blk] = S.bandpass(wind[i:i + blk], c * 0.7, c * 1.6, 1)
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * t / L * 3 - 1)
    base.add(out * swell * 0.11, 0, pan=0.2)
    # A reversed swell into bars 8 and 16.
    for bar in (7, 15):
        rs = S.riser(4 * spb, 0.25)
        base.add(S.lowpass(rs, 1500), bar * 4 * spb, gain=0.5)
    mix = S.reverb(base.buf, 0.88, 0.35, 0.35) + S.reverb(S.echo(bells.buf, 0.75 * spb, 0.45, 0.4), 0.92, 0.2, 0.7)
    mix = S.lowpass(mix, 9000)
    return S.master(mix, 0.75, 1.1)


# ======================================================================================
# CHASE (the killer is close): "Run"
# ======================================================================================

def chase():
    bpm = 150
    spb = 60 / bpm
    s16 = spb / 4
    bars = 32
    L = bars * 4 * spb
    drums = S.Track(L)
    bass = S.Track(L)
    syn = S.Track(L)
    fx = S.Track(L)
    # Two-bar chords: Dm, Eb, Dm, C, Bb, C, Dm, Eb (phrygian dread).
    roots = ["D2", "Eb2", "D2", "C2", "Bb1", "C2", "D2", "Eb2"]
    triads = {"D2": ["D4", "F4", "A4"], "Eb2": ["Eb4", "G4", "Bb4"], "C2": ["C4", "E4", "G4"], "Bb1": ["Bb3", "D4", "F4"]}
    bass_pat = [0, 0, 12, 0, 0, 1, 0, 0, 0, 0, 12, 0, 3, 0, 1, 0]
    for bar in range(bars):
        root = roots[(bar // 2) % 8]
        r = S.midi(root)
        section_b = bar >= 16
        # Drums.
        for b in range(4):
            drums.add(S.kick(1.0, 1.0), (bar * 4 + b) * spb, gain=0.62)
        if bar % 2 == 1:
            drums.add(S.kick(0.8), (bar * 4 + 3.5) * spb, gain=0.45)
        for b in (1, 3):
            drums.add(S.snare(0.95, 180, snappy=0.9), (bar * 4 + b) * spb, gain=0.5)
            drums.add(S.clap(0.8), (bar * 4 + b) * spb, gain=0.3)
        for k in range(16):
            v = 0.35 if k % 4 == 2 else 0.22
            drums.add(S.hat(v, open_=(k % 4 == 2)), bar * 4 * spb + k * s16, gain=0.2, pan=0.35 if k % 2 else -0.2)
        if bar % 8 == 7:
            for k, nt in enumerate(["A2", "F2", "D2", "Bb1", "A1", "F1"]):
                drums.add(S.tom(nt, 0.9), (bar * 4 + 2.5) * spb + k * s16, gain=0.45, pan=-0.5 + k * 0.2)
            fx.add(S.riser(4 * spb, 0.5), bar * 4 * spb, gain=0.5)
        if bar % 8 == 0:
            fx.add(S.impact(0.9, 2.5), bar * 4 * spb, gain=0.5)
        # Bass: gritty 16ths.
        for k in range(16):
            off = bass_pat[k]
            if k in (6, 7) and bar % 2 == 1:
                off = -2 if k == 6 else 0
            bass.add(S.reese(r + off, s16 * 0.9, 0.9, cutoff=700 + 500 * (k % 4 == 0)), bar * 4 * spb + k * s16, gain=0.34)
        # Brass stabs.
        ch = [S.midi(x) for x in triads[root]]
        for b in (0, 1.5, 3):
            syn.add(S.brass_stab(ch, 0.35 * spb, 0.8), (bar * 4 + b) * spb, gain=0.26)
        # Ticking clock high above.
        for k in range(8):
            nt = "D6" if k % 2 == 0 else "A5"
            syn.add(S.pluck(nt, 0.3 * spb, 0.5, bright=0.8), (bar * 4 + k * 0.5) * spb, gain=0.07, pan=0.5 if k % 2 else -0.5)
        # Section B: a siren lead.
        if section_b:
            lead_line = ["D5", "F5", "A5", "Bb5", "A5", "G5", "F5", "E5"]
            nt = lead_line[(bar - 16) % 8]
            syn.add(S.lead(nt, 3.8 * spb, 0.7, vibrato=6.5), bar * 4 * spb, gain=0.3, pan=0.1)
            syn.add(S.lead(S.midi(nt) - 12, 3.8 * spb, 0.5, vibrato=6.5), bar * 4 * spb, gain=0.18, pan=-0.1)
    mix = (S.reverb(drums.buf, 0.6, 0.4, 0.12) + bass.buf + S.reverb(S.echo(syn.buf, 0.75 * spb, 0.3, 0.2), 0.8, 0.3, 0.3)
           + S.reverb(fx.buf, 0.85, 0.3, 0.4))
    mix = S.sidechain(mix, spb, depth=0.25, release=0.12)
    return S.master(mix, 0.92, 1.8)


# ======================================================================================
# SOUND EFFECTS
# ======================================================================================

def sfx():
    out = {}

    def stereo(x):
        x = np.asarray(x)
        return np.vstack([x, x])

    def tail(x, seconds):
        return np.concatenate([x, np.zeros(int(seconds * SR))])

    # A generator comes back on: three rising chimes over a power-up hum.
    n = int(2.0 * SR)
    t = np.arange(n) / SR
    hum = S.saw(55, n, 20) * 0.3 + S.saw(110, n, 20) * 0.2
    hum = S.sweep_lowpass(hum, 200, 2500) * np.minimum(t / 0.3, 1) * np.exp(-t / 1.2)
    x = hum
    for k, nt in enumerate(["A5", "C#6", "E6"]):
        b = S.bell(nt, 0.4, 0.7)
        i = int(k * 0.14 * SR)
        x[i:i + len(b)] += b[: n - i]
    out['sfx_gen_done'] = S.reverb(stereo(tail(x, 1.0)), 0.8, 0.3, 0.35, loops=False)
    # A mistake at a generator: a loud electric buzz and spark.
    n = int(0.7 * SR)
    t = np.arange(n) / SR
    buzz = S.drive(S.square(98, n) * 0.6 + S.saw(147, n, 20) * 0.4, 3) * np.exp(-t / 0.35)
    sparks = S.highpass(S.noise(n), 3000) * (S.RNG.random(n) > 0.97) * np.exp(-t / 0.2)
    out['sfx_gen_fail'] = S.reverb(stereo(tail(buzz * 0.7 + sparks, 0.4)), 0.6, 0.4, 0.2, loops=False)
    # A punch landing.
    n = int(0.4 * SR)
    t = np.arange(n) / SR
    thud = S.kick(1.0, 0.6, 0.4)[:n] + S.lowpass(S.noise(n), 2500) * np.exp(-t / 0.02) * 0.8
    out['sfx_punch'] = stereo(tail(S.drive(thud, 2), 0.1))
    # The spike thrown: a metallic whoosh.
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    wh = S.noise(n)
    wh = S.sweep_lowpass(wh, 600, 6000) * np.sin(np.pi * t / 0.6) ** 2
    ring = np.sin(2 * np.pi * 2300 * t) * np.exp(-t / 0.15) * 0.15 + np.sin(2 * np.pi * 3170 * t) * np.exp(-t / 0.1) * 0.1
    out['sfx_spike_throw'] = S.reverb(stereo(tail(wh * 0.7 + ring, 0.3)), 0.7, 0.3, 0.2, loops=False)
    # The spike hits: a clang and a thud.
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    clang = sum(np.sin(2 * np.pi * f * t) * np.exp(-t / d) * a for f, d, a in [(820, 0.25, 0.5), (1310, 0.18, 0.35), (2210, 0.1, 0.25), (3530, 0.06, 0.15)])
    out['sfx_spike_hit'] = S.reverb(stereo(tail(S.drive(clang + S.kick(0.8, 0.5, 0.9)[:n] * 0.6, 1.5), 0.3)), 0.7, 0.3, 0.25, loops=False)
    # Round start: a huge boom and a dark chord.
    boom = S.impact(1.0, 4.0)
    chord = S.brass_stab([S.midi("D3"), S.midi("A3"), S.midi("D4"), S.midi("Eb4")], 1.2, 0.9)
    x = np.zeros(int(4.5 * SR))
    x[: len(boom)] += boom
    x[: len(chord)] += chord * 0.6
    out['sfx_round_start'] = S.reverb(stereo(x), 0.9, 0.2, 0.45, loops=False)
    # Survivors win: a bright rising arpeggio and a major chord.
    x = np.zeros(int(4.0 * SR))
    for k, nt in enumerate(["D4", "F#4", "A4", "D5", "F#5", "A5"]):
        p = S.pluck(nt, 1.5, 0.8, bright=0.7)
        i = int(k * 0.09 * SR)
        x[i:i + len(p)] += p[: len(x) - i]
    ch = S.pad(["D4", "F#4", "A4", "D5"], 2.0, 0.7, cutoff=3000, attack=0.05, release=1.5)
    i = int(0.5 * SR)
    x[i:i + len(ch)] += ch[: len(x) - i]
    out['sfx_survivors_win'] = S.reverb(stereo(x), 0.85, 0.25, 0.4, loops=False)
    # The killer wins: a falling, heavy sting.
    x = np.zeros(int(4.0 * SR))
    for k, nt in enumerate(["A3", "F3", "D3", "Bb2"]):
        st = S.brass_stab([S.midi(nt), S.midi(nt) + 1, S.midi(nt) + 7], 0.5, 0.9)
        i = int(k * 0.28 * SR)
        x[i:i + len(st)] += st[: len(x) - i]
    b = S.impact(0.9, 3.0)
    i = int(1.1 * SR)
    x[i:i + len(b)] += b[: len(x) - i]
    out['sfx_killer_win'] = S.reverb(stereo(x), 0.9, 0.25, 0.45, loops=False)
    # Countdown tick.
    n = int(0.3 * SR)
    out['sfx_tick'] = stereo(tail(S.bell("E6", 0.05, 0.6)[:n] + S.hat(0.2)[: n] if False else S.bell("E6", 0.05, 0.6)[:n], 0.05))
    for k in out:
        out[k] = S.master(S.fade_edges(out[k]), 0.9, 1.1)
    return out


if __name__ == '__main__':
    import sys
    which = sys.argv[1:] or ['lobby', 'calm', 'chase', 'sfx']
    if 'lobby' in which:
        S.save(os.path.join(OUT, 'music_lobby.ogg'), lobby())
        print('lobby done')
    if 'calm' in which:
        S.save(os.path.join(OUT, 'music_calm.ogg'), calm())
        print('calm done')
    if 'chase' in which:
        S.save(os.path.join(OUT, 'music_chase.ogg'), chase())
        print('chase done')
    if 'sfx' in which:
        for name, x in sfx().items():
            S.save(os.path.join(OUT, name + '.ogg'), x)
        print('sfx done')
