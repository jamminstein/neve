// Engine_Neve
// Vocal chain processor inspired by Neve 1073 / SSL comp / Soothe2
// Signal path: input gain -> saturation -> transient shaper -> compressor -> de-esser -> air EQ -> output gain

Engine_Neve : CroneEngine {
	var pg;
	var <synth;

	var input_gain = 1.0;
	var sat_drive = 0.0;
	var clip_mode = 0;
	var trans_attack = 0.005;
	var trans_sustain = 0.5;
	var trans_mix = 0.0;
	var comp_thresh = 0.9;
	var comp_ratio = 1.5;
	var comp_attack = 0.05;
	var comp_release = 0.4;
	var comp_mix = 0.0;
	var sooth_q = 0.5;
	var sooth_depth = 0.0;
	var air_gain = 0.0;
	var out_gain = 1.0;
	var pan = 1.0;

	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {

		pg = ParGroup.tail(context.xg);

		SynthDef(\neve, {
			arg in_gain = 1.0,
			    drive = 0.0,
			    clipMode = 0,
			    trAttack = 0.005,
			    trSustain = 0.5,
			    trMix = 0.0,
			    cThresh = 0.9,
			    cRatio = 1.5,
			    cAttack = 0.05,
			    cRelease = 0.4,
			    cMix = 0.0,
			    soothQ = 0.5,
			    soothDepth = 0.0,
			    airGain = 0.0,
			    outGain = 1.0,
			    panWidth = 1.0;

			var sig, dry, left, right, mid, side;
			var env, envAttack, envSustain, transientSig;
			var compEnv, compGain, compSig;
			var soothBand, soothEnv, soothGain, soothSig;
			var airSig;
			var lagTime = 0.02;

			// Smooth all parameters to avoid clicks
			in_gain   = Lag.kr(in_gain, lagTime);
			drive     = Lag.kr(drive, lagTime);
			clipMode  = Lag.kr(clipMode, lagTime);
			trAttack  = Lag.kr(trAttack, lagTime);
			trSustain = Lag.kr(trSustain, lagTime);
			trMix     = Lag.kr(trMix, lagTime);
			cThresh   = Lag.kr(cThresh, lagTime);
			cRatio    = Lag.kr(cRatio, lagTime);
			cAttack   = Lag.kr(cAttack, lagTime);
			cRelease  = Lag.kr(cRelease, lagTime);
			cMix      = Lag.kr(cMix, lagTime);
			soothQ    = Lag.kr(soothQ, lagTime);
			soothDepth= Lag.kr(soothDepth, lagTime);
			airGain   = Lag.kr(airGain, lagTime);
			outGain   = Lag.kr(outGain, lagTime);
			panWidth  = Lag.kr(panWidth, lagTime);

			// --- Input ---
			sig = SoundIn.ar([0, 1]) * in_gain;

			// --- Saturation stage ---
			// Blend between tube (tanh, odd harmonics) and tape (softer, even harmonics)
			sig = Select.ar(clipMode < 0.5, [
				// Tape mode (clipMode=1): asymmetric soft clip producing even harmonics
				{
					var shaped = (sig * (1 + (drive * 4))).tanh;
					var asym = (sig * (1 + (drive * 3)) + (drive * 0.15)).tanh;
					// Blend symmetric and asymmetric for even harmonics
					((shaped * 0.5) + (asym * 0.5)) * (1 / (1 + (drive * 0.3)));
				}.value,
				// Tube mode (clipMode=0): classic tanh warm saturation
				{
					(sig * (1 + (drive * 4))).tanh * (1 / (1 + (drive * 0.3)));
				}.value
			]);

			// --- Transient shaper ---
			// Fast envelope follower vs slow envelope follower
			envAttack  = Amplitude.ar(sig, trAttack, trSustain * 4);
			envSustain = Amplitude.ar(sig, trSustain, trSustain * 4);
			// Transient = fast - slow (emphasizes attacks)
			transientSig = sig * (1 + ((envAttack - envSustain).clip(0, 1) * 4));
			sig = ((1 - trMix) * sig) + (trMix * transientSig);

			// --- Compressor ---
			// Simple feed-forward compressor
			env = Amplitude.ar(sig, cAttack, cRelease);
			// Gain computation: above threshold, reduce by ratio
			compGain = Select.ar(env > cThresh, [
				DC.ar(1.0),
				// dB domain compression
				{
					var envDb = env.max(0.0001).log * (20 / 2.302585); // ampdb
					var threshDb = cThresh.max(0.0001).log * (20 / 2.302585);
					var overDb = envDb - threshDb;
					var reducedDb = overDb / cRatio;
					var gainDb = reducedDb - overDb;
					(gainDb * (2.302585 / 20)).exp; // dbamp
				}.value
			]);
			compGain = Lag.ar(compGain, 0.002); // smooth gain changes
			compSig = sig * compGain;
			// Auto makeup gain: compensate for compression
			compSig = compSig * (1 + ((1 - cThresh) * (cRatio - 1) * 0.15));
			// Parallel mix: dry/compressed blend
			sig = ((1 - cMix) * sig) + (cMix * compSig);

			// --- Soothe / De-esser ---
			// Dynamic EQ: detect energy in sibilance band and reduce it
			// Bandpass to detect sibilant energy (4-8 kHz)
			soothBand = BPF.ar(sig, 6000, soothQ.max(0.05));
			soothEnv = Amplitude.ar(soothBand, 0.002, 0.02);
			// Narrow notch reduction proportional to detected energy
			soothGain = 1 - (soothEnv * soothDepth * 12).clip(0, 0.85);
			soothSig = BHiShelf.ar(sig, 5500, 0.7, soothGain.linlin(0.15, 1.0, -12, 0));
			sig = ((1 - soothDepth) * sig) + (soothDepth * soothSig);

			// --- Air EQ ---
			// High shelf boost around 10-12 kHz for "air"
			sig = BHiShelf.ar(sig, 11000, 0.6, airGain);

			// --- Output gain ---
			sig = sig * outGain;

			// --- Soft clipper / limiter ---
			sig = (sig * 1.1).tanh * 0.95;

			// --- Stereo width / mono ---
			// panWidth: 0=mono, 1=stereo
			left  = sig[0];
			right = sig[1];
			mid   = (left + right) * 0.5;
			side  = (left - right) * 0.5 * panWidth;
			sig = [mid + side, mid - side];

			Out.ar(context.out_b, sig);
		}).add;

		context.server.sync;

		synth = Synth(\neve, [
			\in_gain, input_gain,
			\drive, sat_drive,
			\clipMode, clip_mode,
			\trAttack, trans_attack,
			\trSustain, trans_sustain,
			\trMix, trans_mix,
			\cThresh, comp_thresh,
			\cRatio, comp_ratio,
			\cAttack, comp_attack,
			\cRelease, comp_release,
			\cMix, comp_mix,
			\soothQ, sooth_q,
			\soothDepth, sooth_depth,
			\airGain, air_gain,
			\outGain, out_gain,
			\panWidth, pan
		], pg);

		// --- Commands ---

		this.addCommand("input_gain", "f", { arg msg;
			input_gain = msg[1];
			synth.set(\in_gain, input_gain);
		});

		this.addCommand("sat_drive", "f", { arg msg;
			sat_drive = msg[1];
			synth.set(\drive, sat_drive);
		});

		this.addCommand("clip_mode", "f", { arg msg;
			clip_mode = msg[1];
			synth.set(\clipMode, clip_mode);
		});

		this.addCommand("trans_attack", "f", { arg msg;
			trans_attack = msg[1];
			synth.set(\trAttack, trans_attack);
		});

		this.addCommand("trans_sustain", "f", { arg msg;
			trans_sustain = msg[1];
			synth.set(\trSustain, trans_sustain);
		});

		this.addCommand("trans_mix", "f", { arg msg;
			trans_mix = msg[1];
			synth.set(\trMix, trans_mix);
		});

		this.addCommand("comp_thresh", "f", { arg msg;
			comp_thresh = msg[1];
			synth.set(\cThresh, comp_thresh);
		});

		this.addCommand("comp_ratio", "f", { arg msg;
			comp_ratio = msg[1];
			synth.set(\cRatio, comp_ratio);
		});

		this.addCommand("comp_attack", "f", { arg msg;
			comp_attack = msg[1];
			synth.set(\cAttack, comp_attack);
		});

		this.addCommand("comp_release", "f", { arg msg;
			comp_release = msg[1];
			synth.set(\cRelease, comp_release);
		});

		this.addCommand("comp_mix", "f", { arg msg;
			comp_mix = msg[1];
			synth.set(\cMix, comp_mix);
		});

		this.addCommand("sooth_q", "f", { arg msg;
			sooth_q = msg[1];
			synth.set(\soothQ, sooth_q);
		});

		this.addCommand("sooth_depth", "f", { arg msg;
			sooth_depth = msg[1];
			synth.set(\soothDepth, sooth_depth);
		});

		this.addCommand("air_gain", "f", { arg msg;
			air_gain = msg[1];
			synth.set(\airGain, air_gain);
		});

		this.addCommand("out_gain", "f", { arg msg;
			out_gain = msg[1];
			synth.set(\outGain, out_gain);
		});

		this.addCommand("pan", "f", { arg msg;
			pan = msg[1];
			synth.set(\panWidth, pan);
		});
	}

	free {
		synth.free;
	}
}
