// Overdraft's 3D table (#496): the element scenes (sky, ground, glass, particles, grass, lightning), ported from the
// approved prototype's GLSL (docs/overdraft-3d/overdraft-3d.html, src/shaders.js). SceneKit runs them as SCNPrograms;
// every program reads one shared block of uniforms (T3DU), written once a frame (Table3DScene.swift).
// Element order in the weights: x = ember, y = wave, z = bolt, w = leaf.
#include <metal_stdlib>
using namespace metal;
#include <SceneKit/scn_metal>

struct T3DU {
    float4 from;   // the scene a change of suit leaves
    float4 to;     // the scene it arrives at
    float4 w;      // the blend right now (the CPU's, for things without a sweep)
    float4 cam;    // the camera's position
    float4 a;      // time, mix, wipe, flash
    float4 b;      // seed, turn, ground, reduced
    float4 c;      // grow (grass), bolt intensity, focal (points per unit at depth 1), max particle size (points)
    float4 d;      // particle opacity: ember, wave, bolt, leaf
    float4 e;      // turn flow: from (rim s), span to the next seat, phase, velocity (-1 to 1)
    float4 f;      // turn flow: color, strength
    float4 g;      // turn flow: the arc's direction, its brightness, rim length, comet spacing
};

struct T3DNode {
    float4x4 modelTransform;
    float4x4 modelViewTransform;
    float4x4 normalTransform;
    float4x4 modelViewProjectionTransform;
};

constant float3 MOON = float3(-0.110, 0.066, -0.992);
constant float2x2 ROT = float2x2(float2(.8, -.6), float2(.6, .8));

// The prototype's colors are written as screen (sRGB) values; SceneKit's framebuffer encodes what it's given as
// linear light, so every output goes through this first to look the same.
static float3 lin(float3 c) { return pow(max(c, float3(0.)), float3(2.2)); }
static float ss(float a, float b, float x) { float t = clamp((x - a) / (b - a), 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
static float hash2(float2 p) { float3 p3 = fract(float3(p.x, p.y, p.x) * .1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
static float noise2(float2 p) {
    float2 i = floor(p), f = fract(p); f = f * f * (3. - 2. * f);
    return mix(mix(hash2(i), hash2(i + float2(1., 0.)), f.x), mix(hash2(i + float2(0., 1.)), hash2(i + float2(1., 1.)), f.x), f.y);
}
static float fbm(float2 p) { float a = .5, s = 0.; for (int i = 0; i < 4; i++) { s += a * noise2(p); p = ROT * p * 2.03 + float2(17.1, 9.3); a *= .5; } return s; }
static float fbm3(float2 p) { float a = .5, s = 0.; for (int i = 0; i < 3; i++) { s += a * noise2(p); p = ROT * p * 2.03 + float2(17.1, 9.3); a *= .5; } return s; }

struct Env { float t; float4 W; float flash; float seed; float turn; };

// The scene in play, per pixel. A change of suit sweeps in from the horizon (c = 0 arrives first, 1 last) and
// dissolves as it comes; with Reduce Motion it's a plain cross-fade.
static Env envAt(constant T3DU& u, float c) {
    Env e;
    float m = u.a.z > .5 ? ss(0., 1., (u.a.y * 1.7 - clamp(c, 0., 1.)) / .7) : ss(0., 1., u.a.y);
    e.W = mix(u.from, u.to, m); e.t = u.a.x; e.flash = u.a.w; e.seed = u.b.x; e.turn = u.b.y;
    return e;
}
// the scene supports the game: a little dimmer and flatter than the table
static float3 backdropTone(float3 c) { float l = dot(c, float3(.3, .55, .15)); return mix(c, float3(l), .10) * .84; }
static float3 horizonCol(float4 W) { return W.x * float3(.70, .21, .04) + W.y * float3(.085, .19, .40) + W.z * float3(.17, .165, .225) + W.w * float3(.90, .68, .36); }
static float3 zenithCol(float4 W) { return W.x * float3(.055, .018, .018) + W.y * float3(.012, .035, .10) + W.z * float3(.022, .022, .034) + W.w * float3(.17, .30, .38); }

// ---------- the ground under the glass: sea, lava, storm sea, meadow ----------
static float wh(float2 q, float time) {
    float t = time * .35;
    return noise2(q * .55 + float2(t * .6, t * .25)) + .5 * noise2(ROT * q * 1.25 + float2(-t * .5, t * .7)) + .22 * noise2(q * 2.9 + float2(t * .8, -t * .6));
}
static float3 waveG(float2 p, float3 V, float near, float time) {
    float e = .14; float h0 = wh(p, time), hx = wh(p + float2(e, 0.), time), hz = wh(p + float2(0., e), time);
    float k = .62 * (.2 + .8 * near);
    float3 n = normalize(float3(-(hx - h0) / e * k, 1., -(hz - h0) / e * k));
    float fr = pow(1. - max(dot(n, V), 0.), 3.);
    float3 c = mix(float3(.012, .10, .26), float3(.05, .34, .64), ss(.3, 1.5, h0));
    float3 R = reflect(-V, n);
    float3 skyR = mix(float3(.24, .56, .88), float3(.03, .10, .24), clamp(R.y * 1.5, 0., 1.));
    c = mix(c, skyR, .12 + .62 * fr);
    float sp = pow(max(dot(R, MOON), 0.), 70.); c += float3(.85, .95, 1.) * sp * .85;
    float t = time * .22; float2 w = p * .85 + n.xz * 1.4;
    float c1 = 1. - abs(2. * noise2(w + float2(t, -t * .6)) - 1.);
    float c2 = 1. - abs(2. * noise2(ROT * w * 1.6 + float2(-t * .8, t) + 3.1) - 1.);
    float ca = pow(c1 * c2, 2.6);
    c += float3(.30, .72, .95) * ca * .42 * near;
    return c;
}
static float3 emberG(float2 p, float near, float t) {
    float n = fbm3(p * .45);
    float crust = fbm3(p * 1.6 + n * 2.);
    float pulse = .65 + .35 * sin(t * .7 + n * 9.);
    float hot = ss(.46, .74, fbm3(p * .33 + float2(t * .02, -t * .015)) + .10 * sin(t * .4 + n * 6.));
    float vein = pow(1. - abs(2. * noise2(p * .75 + n * 2.2) - 1.), 8.);
    float3 c = mix(float3(.05, .02, .022), float3(.15, .055, .035), crust);
    c += float3(1., .36, .06) * vein * (.22 + .95 * hot) * pulse;
    c += float3(.95, .25, .03) * hot * .42 * (.55 + .45 * crust);
    c += float3(1., .78, .32) * pow(hot * vein, 2.) * .9;
    return c;
}
static float3 leafG(float2 p, float near, float t) {
    // a meadow in late-afternoon sun, seen from above (#496, Nov 17): turf combed by the wind, golden dry patches
    // among the green, wind waves rolling through it, slow cloud shadows, and small flowers near the table
    float2 wind = float2(.92, .38);
    float2 q = float2(dot(p, wind), dot(p, float2(-wind.y, wind.x)));
    float macro = fbm3(p * .07 + 3.1);
    float pv = fbm3(p * .45 + 7.);
    float streak = noise2(q * float2(2.2, 11.)) * .55 + noise2(q * float2(5., 26.) + 4.) * .45;
    float fine = noise2(p * 23.);
    float3 lush = mix(float3(.04, .095, .022), float3(.17, .29, .065), ss(.25, .85, pv * .55 + streak * .45 + fine * .12 * near));
    float3 dry = mix(float3(.22, .17, .055), float3(.56, .44, .15), ss(.2, .9, pv * .5 + streak * .55));
    float3 c = mix(lush, dry, ss(.42, .70, macro) * .85);
    // wind waves: bands of sheen moving downwind, where bent blades show their lighter sides to the low sun
    float wave = fbm3(q * float2(.20, .55) - float2(t * .55, 0.));
    float sheen = ss(.50, .80, wave);
    c = mix(c, c * 1.45 + float3(.15, .11, .03), sheen * .5 * (.55 + .45 * streak));
    // the low sun, and the shadows of clouds drifting over
    float cloud = ss(.44, .72, fbm3(p * .032 + float2(t * .011, t * .004)));
    c *= mix(1.10, .64, cloud);
    c += float3(.09, .055, .0) * (1. - cloud) * .55;
    // small flowers, near the table only: mostly white, some yellow, a few violet
    float2 cell = floor(p * 5.); float h = hash2(cell);
    float2 jit = (float2(hash2(cell + 1.7), hash2(cell + 5.3)) - .5) * .5;
    float fl = step(.955, h) * ss(.24, .07, length(fract(p * 5.) - .5 - jit)) * near;
    float3 fc = h > .988 ? float3(.78, .62, .95) : (h > .972 ? float3(1., .86, .30) : float3(.97, .95, .86));
    c = mix(c, fc * (1.05 - .4 * cloud), fl * .8);
    return c;
}
static float3 boltG(float2 p, float3 V, float near, thread const Env& e) {
    // a dark storm sea: slate swells, lit only by the sky and the strikes
    float ee = .16; float h0 = wh(p * .8, e.t), hx = wh(p * .8 + float2(ee, 0.), e.t), hz = wh(p * .8 + float2(0., ee), e.t);
    float k = .9 * (.2 + .8 * near);
    float3 n = normalize(float3(-(hx - h0) / ee * k, 1., -(hz - h0) / ee * k));
    float fr = pow(1. - max(dot(n, V), 0.), 3.);
    float3 c = mix(float3(.022, .024, .034), float3(.10, .105, .145), ss(.35, 1.5, h0));
    float3 R = reflect(-V, n);
    float3 skyR = mix(float3(.27, .265, .34), float3(.05, .05, .07), clamp(R.y * 1.4, 0., 1.));
    c = mix(c, skyR, .14 + .62 * fr);
    float glint = pow(max(R.y, 0.), 3.) * ss(.9, 1.5, h0);
    c += float3(.26, .22, .42) * glint * .55;
    float m = fbm3(p * .35 + e.seed);
    float a1 = pow(1. - abs(2. * noise2(p * .42 + m * 2.6 + e.seed) - 1.), 30.);
    c += float3(.80, .74, 1.) * a1 * e.flash * .9 * near;
    c += float3(.55, .48, .95) * e.flash * (.10 + .55 * fr + .25 * glint);
    return c;
}
static float3 elementGround(float2 p, float3 V, float dist, thread const Env& e) {
    float near = 1. - ss(8., 42., dist);
    float3 col = float3(0.);
    if (e.W.x > .002) col += e.W.x * emberG(p, near, e.t);
    if (e.W.y > .002) col += e.W.y * waveG(p, V, near, e.t);
    if (e.W.z > .002) col += e.W.z * boltG(p, V, near, e);
    if (e.W.w > .002) col += e.W.w * leafG(p, near, e.t);
    return col;
}

// ---------- shared vertex shapes ----------
struct PosIn { float3 position [[attribute(SCNVertexSemanticPosition)]]; };
struct PosUVIn { float3 position [[attribute(SCNVertexSemanticPosition)]]; float2 uv [[attribute(SCNVertexSemanticTexcoord0)]]; };
struct WorldOut { float4 position [[position]]; float3 world; float2 uv; };

vertex WorldOut t3d_world_vert(PosIn in [[stage_in]], constant SCNSceneBuffer& scn_frame [[buffer(0)]], constant T3DNode& scn_node [[buffer(1)]]) {
    WorldOut o; float4 w = scn_node.modelTransform * float4(in.position, 1.);
    o.world = w.xyz; o.uv = float2(0.); o.position = scn_frame.viewProjectionTransform * w; return o;
}
vertex WorldOut t3d_worlduv_vert(PosUVIn in [[stage_in]], constant SCNSceneBuffer& scn_frame [[buffer(0)]], constant T3DNode& scn_node [[buffer(1)]]) {
    WorldOut o; float4 w = scn_node.modelTransform * float4(in.position, 1.);
    o.world = w.xyz; o.uv = in.uv; o.position = scn_frame.viewProjectionTransform * w; return o;
}

// ---------- the ground far below the glass, to the horizon ----------
fragment float4 t3d_ground_frag(WorldOut in [[stage_in]], constant T3DU& u [[buffer(2)]]) {
    float3 vW = in.world;
    Env e = envAt(u, 1. - clamp((12. - vW.z) / 70., 0., 1.) + (noise2(vW.xz * .12) - .5) * .3);
    float3 V = normalize(u.cam.xyz - vW); float dist = length(u.cam.xyz - vW);
    float3 col = elementGround(vW.xz, V, dist, e);
    float fog = 1. - exp(-dist * .016);
    col = mix(col, horizonCol(e.W), fog * .97);
    return float4(lin(backdropTone(col)), 1.);
}

// ---------- the turn flow: light running round the rim in turn order (#496, Nov 17) ----------
// Drawn by the glass itself (opaque, so it never depends on blending). The whole rim flows faintly in play's
// direction; the arc from whoever is on to whoever is next is bright, and whoever is next glows. Reduce Motion: a
// still arc that brightens toward whoever is next.
constant float RX = 2.2, A0 = 3.2, QA = 3.4557519, PERIM = 26.6230077, SPACING = 26.6230077 / 24.;

// Where a point on the glass is round the rim (s, as Table3D.rimPoint counts it) and how far out (k: 1 is the felt's edge).
static float2 rimSK(float2 p) {
    float x = p.x, z = p.y;
    if (z > A0) { float2 d = float2(x, z - A0); float th = atan2(d.x, d.y); return float2(th <= 0. ? -th * RX : PERIM - th * RX, length(d) / RX); }
    if (z < -A0) { float2 d = float2(x, z + A0); return float2(QA + 2. * A0 + atan2(-d.y, -d.x) * RX, length(d) / RX); }
    return x < 0. ? float2(QA + (A0 - z), -x / RX) : float2(3. * QA + 2. * A0 + (z + A0), x / RX);
}

// The flow's color and how much of it (0 to 1) at a point on the glass.
static float4 turnFlow(float2 p, constant T3DU& u) {
    if (u.f.w < .001) return float4(0.);
    float2 sk = rimSK(p);
    float v = (sk.y - .975) / (1.09 - .975);
    if (v <= 0. || v >= 1.) return float4(0.);
    float s = sk.x, L = u.e.y;
    float x = (s - u.e.x) * u.g.x; float rel = x - PERIM * floor(x / PERIM);   // past whoever is on, in the arc's direction
    float inArc = ss(0., .3, rel) * (1. - ss(L - .45, L, rel));
    float across = ss(0., .3, v) * (1. - ss(.7, 1., v));
    float dn = abs(rel - L); dn = min(dn, PERIM - dn);                         // how far from whoever is next
    float b;
    if (u.b.w > .5) {
        b = inArc * u.g.y * (.30 + .65 * clamp(rel / max(L, .01), 0., 1.)) + exp(-dn * dn / .3) * .85 * u.g.y;
    } else {
        float fr = fract((s - u.e.z) / SPACING), vd = clamp(u.e.w, -1., 1.);
        float fwd = pow(fr, 5.) * ss(1., .9, fr), back = pow(1. - fr, 5.) * ss(0., .1, fr);
        float comet = mix(back, fwd, vd * .5 + .5) * 1.6;                     // the bright head leads, its tail trails
        float glow = exp(-dn * dn / .35) * (.75 + .2 * sin(u.a.x * 3.4));
        b = .10 * comet + inArc * u.g.y * (.85 * comet + .20) + glow * u.g.y;   // faint all round, bright on the arc
    }
    float a = clamp(b * across * u.f.w, 0., .9);
    return float4(mix(u.f.rgb, float3(1.), .45 * clamp(b - .4, 0., 1.)), a);
}

// ---------- the glass: a frosted slab the element shows through, its rim lit on your turn ----------
fragment float4 t3d_glass_frag(WorldOut in [[stage_in]], constant T3DU& u [[buffer(2)]]) {
    float3 vW = in.world;
    Env e = envAt(u, .55);
    float3 I = normalize(vW - u.cam.xyz); float3 N = float3(0., 1., 0.);
    float3 T = refract(I, N, 1. / 1.42);
    float tt = (u.b.z - vW.y) / min(T.y, -.05); float3 g = vW + T * tt;
    float2 fr = (float2(noise2(vW.xz * 7.), noise2(vW.xz * 7. + 31.)) - .5) * .55;
    float3 col = elementGround(g.xz * .8 + fr, -T, length(g - u.cam.xyz) * .6, e);
    float3 tint = horizonCol(e.W);
    col = col * .74 + tint * .12 + float3(.07);
    float grain = hash2(floor(vW.xz * 90.)); col += (grain - .5) * .022;
    float f = pow(1. - max(dot(-I, N), 0.), 4.);
    float3 R = reflect(I, N);
    float3 sky = mix(horizonCol(e.W), zenithCol(e.W), clamp(R.y * 1.6, 0., 1.));
    col = mix(col, sky + .06, .06 + .50 * f);
    col += float3(.9, .95, 1.) * pow(max(dot(R, MOON), 0.), 28.) * .35 * f;
    float2 oval = float2(2.2 * 1.11, 5.4 - 2.2);
    float ed = length(float2(vW.x, max(abs(vW.z) - oval.y, 0.))) / oval.x;
    float pulse = e.turn * (.75 + .25 * sin(e.t * 3.2));
    col += (tint * .5 + .5) * (ss(.90, .995, ed) * .30 + ss(.975, 1., ed) * .5);
    col += (tint * .8 + .2) * pulse * (ss(.72, 1., ed) * .75 + ss(.94, 1., ed) * .7);
    col += float3(.5, .42, .9) * e.flash * .28;
    float4 fl = turnFlow(vW.xz, u);
    col = mix(col, fl.rgb, fl.a);
    return float4(lin(col), 1.);
}

fragment float4 t3d_edge_frag(WorldOut in [[stage_in]], constant T3DU& u [[buffer(2)]]) {
    Env e = envAt(u, .55);
    float3 tint = horizonCol(e.W) * .6 + .4;
    float v = in.uv.y;
    float lines = ss(.80, 1., v) * .9 + ss(.16, 0., v) * .35;
    float pulse = e.turn * (.75 + .25 * sin(e.t * 3.2));
    float3 col = tint * (.22 + lines) + zenithCol(e.W) * .5 + (horizonCol(e.W) * .8 + .2) * pulse * .9;
    col += float3(.5, .42, .9) * e.flash * .6;
    float a = .62 + .38 * lines;
    return float4(lin(col) * a, a);
}

// ---------- the sky: a dome that follows the camera ----------
struct SkyOut { float4 position [[position]]; float3 dir; };
vertex SkyOut t3d_sky_vert(PosIn in [[stage_in]], constant SCNSceneBuffer& scn_frame [[buffer(0)]], constant T3DU& u [[buffer(2)]]) {
    SkyOut o; o.dir = in.position;
    o.position = scn_frame.viewProjectionTransform * float4(u.cam.xyz + in.position, 1.);
    return o;
}
fragment float4 t3d_sky_frag(SkyOut in [[stage_in]], constant T3DU& u [[buffer(2)]]) {
    float3 d = normalize(in.dir); float h = d.y;
    Env e = envAt(u, clamp(h * 2.2, 0., 1.) * .7 + (noise2(d.xz * 3.) - .5) * .25);
    float4 W = e.W; float time = e.t;
    float g = pow(1. - clamp(h, 0., 1.), 3.2);
    float3 col = mix(zenithCol(W), horizonCol(W), g);
    float2 sp = d.xz / (abs(h) + .2);
    float edge = ss(0., .09, h);
    float3 add = float3(0.);
    if (W.x > .002) { float s = fbm(sp * 1.3 + float2(0., time * .03));
        add += W.x * (float3(.95, .32, .05) * g * (s - .42) * 1.1 - float3(.05, .02, .02) * s * (1. - g)); }
    if (W.y > .002) { float s = fbm(sp * 1.1 + float2(time * .015, 0.));
        add += W.y * float3(.35, .6, .9) * (s - .4) * .32 * (g + .25);
        float2 sq = floor(float2(atan2(d.x, -d.z) * 150., h * 150.));
        add += W.y * float3(.8, .9, 1.) * step(.994, hash2(sq)) * ss(.10, .35, h) * .7 * (.6 + .4 * sin(time * 2. + sq.x)); }
    float3 add2 = float3(0.);
    if (W.z > .002) {
        // storm: cloud decks rolling at different speeds; charcoal bodies, slate bellies, lit edges, violet under-glow
        float t = time; float az = atan2(d.x, -d.z);
        float2 cp = float2(az * 2.2, h * 9.);
        float d1 = fbm(sp * .55 + float2(t * .020, t * .006));
        float d2 = fbm(sp * 1.35 + float2(-t * .034, t * .010) + d1 * 1.3);
        float d3 = fbm(cp + float2(t * .012, -t * .004) + d1);
        float low = 1. - ss(.05, .30, h);
        float dm = mix(d1, d3, low);
        float body = ss(.34, .66, dm);
        float wisps = ss(.36, .70, d2);
        float3 dark = float3(.022, .023, .034), slate = float3(.26, .265, .31);
        float3 cl = mix(slate * (.50 + .75 * g), dark, body);
        cl = mix(cl, mix(dark * 1.3, slate * .85, d2), wisps * .5);
        float edgeL = ss(.34, .46, dm) * (1. - ss(.46, .62, dm));
        cl += float3(.42, .40, .52) * edgeL * (.30 + .55 * g);
        cl += float3(.26, .14, .48) * (1. - body) * low * .40;
        float veil = ss(.48, .72, fbm3(float2(az * 3.2 + t * .006, 1.3))) * (1. - ss(.0, .20, h));
        cl = mix(cl, float3(.15, .15, .20), veil * .55);
        for (int k = 0; k < 2; k++) {   // silent flickers inside the clouds
            float fk = float(k), per = 2.6 + fk * 1.3, ph = t / per + fk * .37, tc = floor(ph), uu = fract(ph);
            float2 c0 = float2((hash2(float2(tc, fk * 7.)) - .5) * .9, .05 + .16 * hash2(float2(tc, 3. + fk)));
            float env = exp(-pow((uu - .30) / .07, 2.)) + .6 * exp(-pow((uu - .46) / .06, 2.));
            float gl = exp(-(pow(az - c0.x, 2.) / .020 + pow(h - c0.y, 2.) / .006));
            cl += float3(.62, .56, .95) * gl * env * (.35 + .9 * body) * .42 * (1. - u.b.w);   // none with Reduce Motion
        }
        cl += float3(.92, .86, 1.) * e.flash * (.10 + 1.1 * (1. - body) * (.35 + .65 * wisps) + .55 * edgeL);
        cl = mix(cl, float3(.20, .20, .27), (1. - ss(.0, .035, h)) * .6);
        float3 base = mix(zenithCol(W), horizonCol(W), g);
        add2 += W.z * (cl - base);
    }
    if (W.y > .002) {
        // dusk over open water: a low bank of cloud, moonlit along its top, and the moon
        float az0 = atan2(d.x, -d.z);
        float bank = ss(.42, .68, fbm(float2(az0 * 2.6 + time * .004, h * 13.))) * (1. - ss(.03, .24, h)) * ss(-.01, .03, h);
        float mm = max(dot(d, MOON), 0.);
        add2 += W.y * bank * (float3(.015, .03, .07) - mix(zenithCol(W), horizonCol(W), g)) * .75;
        add2 += W.y * bank * float3(.35, .5, .75) * pow(mm, 6.) * .5;
        add2 += W.y * (float3(.55, .75, 1.) * (pow(mm, 24.) * .40 + pow(mm, 220.) * .5) + float3(.95, .98, 1.) * ss(.99982, .99992, mm));
    }
    if (W.x > .002) {
        // a volcanic skyline: a dark ridge with one cone, its crater lighting the smoke above it
        float az = atan2(d.x, -d.z); float3 base = mix(zenithCol(W), horizonCol(W), g);
        float cone = exp(-pow((az + .13) / .19, 2.));
        float ridge = .022 + .06 * fbm3(float2(az * 4., 9.)) + .012 * noise2(float2(az * 30., 2.)) + .15 * cone;
        float m = 1. - ss(ridge - .003, ridge + .005, h);
        float3 rock = mix(float3(.045, .02, .02), base, .22);
        float glow = exp(-pow((az + .13) / .13, 2.)) * exp(-max(h - .17, 0.) * 10.) * (.8 + .2 * sin(time * .9));
        float3 f = base + float3(1., .42, .08) * glow * .75 * (.6 + .6 * fbm3(sp * 2. + float2(0., time * .06)));
        f = mix(f, rock, m * (.5 + .5 * ss(-.01, .04, h)));
        add2 += W.x * (f - base);
    }
    if (W.w > .002) {
        // golden hour: a low sun in haze over a far, soft line of land (no trees)
        float3 SUN = normalize(float3(.16, .075, -1.));
        float sd = max(dot(d, SUN), 0.);
        float3 base = mix(zenithCol(W), horizonCol(W), g);
        float3 f = base;
        f += float3(1., .70, .30) * (pow(sd, 5.) * .30 + pow(sd, 48.) * .55) + float3(1., .96, .82) * ss(.9988, .9995, sd);
        float hz = fbm3(sp * .8 + float2(time * .01, 0.)); f += float3(.30, .14, .03) * (hz - .5) * g * .6;
        float az = atan2(d.x, -d.z);
        float line = .045 + .10 * fbm3(float2(az * 5., 1.7)) + .02 * noise2(float2(az * 22., 4.));
        float tree = 1. - ss(line - .022, line + .028, h);
        float3 wood = mix(float3(.07, .13, .04), horizonCol(W), .22 + .40 * pow(sd, 4.));
        f = mix(f, wood, tree * (.45 + .5 * ss(-.01, .05, h)));
        float2 gq = float2(az * 9., h * 38.); float2 gi = floor(gq), gf = fract(gq) - .5; float r1 = hash2(gi), r2 = hash2(gi + 3.3);
        float disc = ss(.34, .20, length(gf - float2(r1 - .5, r2 - .5) * .4)) * step(.5, r1) * tree;
        f += float3(1., .85, .45) * disc * .20 * (.6 + .4 * sin(time * .6 + r2 * 6.));
        add2 += W.w * (f - base);
    }
    col += add * edge + add2;
    return float4(lin(backdropTone(col)), 1.);
}

// ---------- particles: embers, spray, storm motes, leaves and pollen (camera-facing quads) ----------
struct PartIn {
    float3 position [[attribute(SCNVertexSemanticPosition)]];   // xy: the quad's corner, z: the kind
    float2 s0 [[attribute(SCNVertexSemanticTexcoord0)]];
    float2 s1 [[attribute(SCNVertexSemanticTexcoord1)]];
};
struct PartOut { float4 position [[position]]; float2 q; float a; float r; float3 c; float tw; float kind; float op; };

vertex PartOut t3d_part_vert(PartIn in [[stage_in]], constant SCNSceneBuffer& scn_frame [[buffer(0)]], constant T3DU& u [[buffer(2)]]) {
    float4 S = float4(in.s0, in.s1); float kind = in.position.z;
    float t = u.a.x, G = u.b.z; float3 p; float life; float size; float vA; float vR = 0.; float vT = 1.; float3 vC;
    // round the table where the aerial camera sees the scene: beside it near you, and out past the far end (never over it)
    float zz = 7. - S.y * 50., ux = (S.x - .5) * 2.;
    float2 b = float2(zz > -9. ? sign(ux) * (3.4 + abs(ux) * 11.) : ux * 24., zz);
    float H = 7.5;
    if (kind < .5) {
        life = fract(S.z + t * (.05 + .06 * S.w));
        p = float3(b.x + sin(t * .8 + S.w * 20.) * .55 * life, G + life * H, b.y + cos(t * .6 + S.z * 20.) * .45 * life);
        vA = sin(life * 3.1416) * (.6 + .4 * sin(t * 6. + S.w * 40.)); size = .09 + .10 * S.w; vC = mix(float3(1., .35, .05), float3(1., .8, .35), S.z);
    } else if (kind < 1.5) {
        life = fract(S.z + t * .05);
        p = float3(b.x + sin(t * .2 + S.w * 9.) * .6, G + .12 + S.w * 2.6 + life * .7, b.y);
        vA = sin(life * 3.1416) * (.45 + .55 * sin(t * 2. + S.w * 30.)) * .8; size = .06 + .06 * S.z; vC = float3(.72, .92, 1.);
    } else if (kind < 2.5) {
        life = fract(S.z + t * .08);
        p = float3(b.x, G + .3 + S.w * 5.5, b.y) + float3(sin(t * 1.7 + S.w * 30.), sin(t * 2.3 + S.z * 30.), cos(t * 1.9 + S.x * 30.)) * .28;
        vA = sin(life * 3.1416) * pow(.5 + .5 * sin(t * 5. + S.w * 50.), 3.); size = .06 + .07 * S.z; vC = float3(.80, .72, 1.);
    } else {
        life = fract(S.z + t * (.035 + .03 * S.w));
        p = float3(b.x + sin(t * .5 + S.w * 20.) * .9 + life * 1.6, G + (1. - life) * H, b.y + cos(t * .4 + S.z * 20.) * .6);
        vA = ss(0., .08, life) * ss(1., .9, life); size = .26 + .16 * S.w; vR = t * (.5 + S.z) + S.w * 6.;
        vT = .35 + .65 * abs(cos(t * (.8 + S.x) + S.z * 9.));
        vC = mix(mix(float3(.25, .55, .14), float3(.55, .70, .18), S.x), float3(.85, .62, .16), step(.72, S.w));
        if (S.x > .45) {   // pollen drifting downwind, glinting as it turns in the low sun
            float dr = fract(S.w + t * .012);
            p = float3(b.x + (dr - .5) * 6. + sin(t * .3 + S.w * 20.) * 1.2, G + .4 + S.w * 4. + sin(t * .4 + S.z * 20.) * .4, b.y + (dr - .5) * 2.4);
            vA = (.45 + .55 * pow(.5 + .5 * sin(t * 2.1 + S.z * 40.), 4.)) * ss(0., .1, dr) * ss(1., .9, dr);
            size = .05 + .05 * S.z; vT = -1.; vC = float3(1., .9, .62);
        }
    }
    float4 mv = scn_frame.viewTransform * float4(p, 1.);
    float depth = max(-mv.z, .1);
    vA *= ss(1.2, 3.5, -mv.z);
    float px = min(size * u.c.z / depth, u.c.w);
    float hs = px * .5 * depth / u.c.z;
    mv.xy += in.position.xy * hs;
    PartOut o;
    o.position = scn_frame.projectionTransform * mv;
    o.q = in.position.xy * .5; o.a = vA; o.r = vR; o.c = vC; o.tw = vT; o.kind = kind;
    int ki = int(kind + .5);
    o.op = ki == 0 ? u.d.x : ki == 1 ? u.d.y : ki == 2 ? u.d.z : u.d.w;
    return o;
}
fragment float4 t3d_part_frag(PartOut in [[stage_in]]) {
    float2 q = in.q; float a; float3 col;
    if (in.kind > 2.5 && in.tw < 0.) { float r = length(q) * 2.; a = exp(-r * r * 4.) * .8; col = in.c; }
    else if (in.kind > 2.5) {
        float c = cos(in.r), s = sin(in.r); q = float2(c * q.x - s * q.y, s * q.x + c * q.y); q.y /= in.tw;
        float lens = max(length(q - float2(0., .26)), length(q + float2(0., .26)));
        a = ss(.50, .46, lens);
        float vein = ss(.03, .0, abs(q.y)) * .25;
        col = in.c * (1. - vein) * (.75 + .5 * (q.x + .3));
    } else { float r = length(q) * 2.; a = exp(-r * r * 5.) + .6 * exp(-r * r * 40.); col = in.c; }
    float al = clamp(a * in.a * in.op, 0., 1.);
    if (al < .004) discard_fragment();
    return float4(lin(col) * al, al);
}
static float4 partColor(PartOut in) {
    float2 q = in.q; float r = length(q) * 2.;
    float a = exp(-r * r * 5.) + .6 * exp(-r * r * 40.);
    return float4(lin(in.c * clamp(a * in.a * in.op, 0., 1.)), 1.);
}
// embers, spray and storm motes add light (additive blending)
fragment float4 t3d_part_add_frag(PartOut in [[stage_in]]) {
    float4 c = partColor(in);
    if (max(c.r, max(c.g, c.b)) < .004) discard_fragment();
    return c;
}

// ---------- the meadow: tall grass in the wind (Leaf) ----------
struct GrassIn {
    float3 position [[attribute(SCNVertexSemanticPosition)]];   // the blade's shape: x across, y up (0 to 1)
    float2 off [[attribute(SCNVertexSemanticTexcoord0)]];       // where the blade stands (x, z)
    float2 r0 [[attribute(SCNVertexSemanticTexcoord1)]];
    float3 r1 [[attribute(SCNVertexSemanticNormal)]];
};
struct GrassOut { float4 position [[position]]; float h; float fog; float r; float gust; float lit; };
vertex GrassOut t3d_grass_vert(GrassIn in [[stage_in]], constant SCNSceneBuffer& scn_frame [[buffer(0)]], constant T3DU& u [[buffer(2)]]) {
    float4 R = float4(in.r0, in.r1.xy); float t = in.position.y; float time = u.a.x;
    float clump = noise2(in.off * .35);
    float hgt = (.45 + .75 * R.x) * (.75 + .6 * clump) * in.r1.z * u.c.x;   // r1.z: near grass grows taller
    float ang = R.y * 6.283; float2 dv = float2(cos(ang), sin(ang));
    float3 p = float3(in.off.x, u.b.z, in.off.y);
    p.xz += dv * in.position.x * .08 * (1. - t * .8);
    // gusts roll downwind across the field: each blade bends with the wave passing over it
    float2 wind = float2(.92, .38);
    float w = dot(in.off, wind);
    float gust = .5 + .5 * sin(w * .55 - time * 1.6) * (.6 + .4 * sin(w * .17 + time * .5)) ;
    float flutter = sin(time * 3.1 + R.w * 20. + in.off.y) * .05;
    float bend = (.10 + .28 * gust + flutter) * t * t * hgt;
    p.xz += wind * bend + dv * .16 * t * t * (R.z - .5);
    p.y += t * hgt * (1. - .10 * t * gust);
    GrassOut o; o.h = t; o.r = R.w; o.gust = gust;
    o.lit = .5 + .5 * dot(normalize(dv), normalize(float2(.16, -1.)));   // facing the low sun: brighter tips
    float4 mv = scn_frame.viewTransform * float4(p, 1.); o.fog = 1. - exp(mv.z * .016);
    o.position = scn_frame.projectionTransform * mv;
    return o;
}
fragment float4 t3d_grass_frag(GrassOut in [[stage_in]]) {
    float3 base = mix(float3(.022, .06, .016), float3(.14, .27, .055), in.h);
    float3 tip = mix(float3(.40, .54, .13), float3(.95, .76, .28), in.r);
    float3 c = mix(base, tip, in.h * in.h * (.55 + .45 * in.r));
    // backlit by the late sun: tips glow warm, more where the gust bends them toward the light
    c += float3(.36, .24, .06) * pow(in.h, 3.) * (.35 + .65 * in.lit) * (.5 + .7 * in.gust);
    c = mix(c, float3(.90, .68, .36), in.fog * .97);
    return float4(lin(c), 1.);
}

// ---------- lightning: a branching bolt, rebuilt for each strike ----------
struct BoltOut { float4 position [[position]]; float2 ua; };
vertex BoltOut t3d_bolt_vert(PosUVIn in [[stage_in]], constant SCNSceneBuffer& scn_frame [[buffer(0)]], constant T3DNode& scn_node [[buffer(1)]]) {
    BoltOut o; o.ua = in.uv; o.position = scn_frame.viewProjectionTransform * (scn_node.modelTransform * float4(in.position, 1.)); return o;
}
fragment float4 t3d_bolt_frag(BoltOut in [[stage_in]], constant T3DU& u [[buffer(2)]]) {
    float d = abs(in.ua.x);
    float core = ss(.16, .03, d);
    float glow = pow(max(1. - d, 0.), 3.);
    float3 col = float3(1.) * core * 1.3 + float3(.62, .48, 1.) * glow * .75;
    float k = in.ua.y * u.c.y;
    return float4(lin(col * k), 1.);
}
