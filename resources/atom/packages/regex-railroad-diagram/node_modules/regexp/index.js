function parse(n) {
  if ("string" != typeof n) {
    var t = new TypeError("The regexp to parse must be represented as a string.");
    throw t;
  }
  return index = 1, cgs = {}, parser.parse(n);
}

function Token(n) {
  this.type = n, this.offset = Token.offset(), this.text = Token.text();
}

function Alternate(n, t) {
  Token.call(this, "alternate"), this.left = n, this.right = t;
}

function Match(n) {
  Token.call(this, "match"), this.body = n.filter(Boolean);
}

function Group(n, t) {
  Token.call(this, n), this.body = t;
}

function CaptureGroup(n, t) {
  Group.call(this, "capture-group"), this.index = cgs[this.offset] || (cgs[this.offset] = index++), 
  this.body = n, t && (this.name = t);
}

function Quantified(n, t) {
  Token.call(this, "quantified"), this.body = n, this.quantifier = t;
}

function Quantifier(n, t) {
  Token.call(this, "quantifier"), this.min = n, this.max = t, this.greedy = !0;
}

function CharSet(n, t) {
  Token.call(this, "charset"), this.invert = n, this.body = t;
}

function CharacterRange(n, t) {
  Token.call(this, "range"), this.start = n, this.end = t;
}

function Literal(n) {
  Token.call(this, "literal"), this.body = n, this.escaped = this.body != this.text;
}

function Unicode(n) {
  Token.call(this, "unicode"), this.code = n.toUpperCase();
}

function Hex(n) {
  Token.call(this, "hex"), this.code = n.toUpperCase();
}

function Octal(n) {
  Token.call(this, "octal"), this.code = n.toUpperCase();
}

function BackReference(n) {
  Token.call(this, "back-reference"), this.code = n.toUpperCase();
}

function ControlCharacter(n) {
  Token.call(this, "control-character"), this.code = n.toUpperCase();
}

var parser = function() {
  function n(n, t) {
    function r() {
      this.constructor = n;
    }
    r.prototype = t.prototype, n.prototype = new r();
  }
  function t(n, t, r, l, u) {
    function e(n, t) {
      function r(n) {
        function t(n) {
          return n.charCodeAt(0).toString(16).toUpperCase();
        }
        return n.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\x08/g, "\\b").replace(/\t/g, "\\t").replace(/\n/g, "\\n").replace(/\f/g, "\\f").replace(/\r/g, "\\r").replace(/[\x00-\x07\x0B\x0E\x0F]/g, function(n) {
          return "\\x0" + t(n);
        }).replace(/[\x10-\x1F\x80-\xFF]/g, function(n) {
          return "\\x" + t(n);
        }).replace(/[\u0180-\u0FFF]/g, function(n) {
          return "\\u0" + t(n);
        }).replace(/[\u1080-\uFFFF]/g, function(n) {
          return "\\u" + t(n);
        });
      }
      var l, u;
      switch (n.length) {
       case 0:
        l = "end of input";
        break;

       case 1:
        l = n[0];
        break;

       default:
        l = n.slice(0, -1).join(", ") + " or " + n[n.length - 1];
      }
      return u = t ? '"' + r(t) + '"' : "end of input", "Expected " + l + " but " + u + " found.";
    }
    this.expected = n, this.found = t, this.offset = r, this.line = l, this.column = u, 
    this.name = "SyntaxError", this.message = e(n, t);
  }
  function r(n) {
    function r() {
      return n.substring(yu, ku);
    }
    function l() {
      return yu;
    }
    function u(t) {
      function r(t, r, l) {
        var u, e;
        for (u = r; l > u; u++) e = n.charAt(u), "\n" === e ? (t.seenCR || t.line++, t.column = 1, 
        t.seenCR = !1) : "\r" === e || "\u2028" === e || "\u2029" === e ? (t.line++, t.column = 1, 
        t.seenCR = !0) : (t.column++, t.seenCR = !1);
      }
      return wu !== t && (wu > t && (wu = 0, Tu = {
        line: 1,
        column: 1,
        seenCR: !1
      }), r(Tu, wu, t), wu = t), Tu;
    }
    function e(n) {
      gu > ku || (ku > gu && (gu = ku, xu = []), xu.push(n));
    }
    function o(n) {
      var t = 0;
      for (n.sort(); t < n.length; ) n[t - 1] === n[t] ? n.splice(t, 1) : t++;
    }
    function c() {
      var t, r, l, u, o;
      return t = ku, r = a(), null !== r ? (l = ku, 124 === n.charCodeAt(ku) ? (u = bt, 
      ku++) : (u = null, 0 === Ru && e(kt)), null !== u ? (o = c(), null !== o ? (u = [ u, o ], 
      l = u) : (ku = l, l = vt)) : (ku = l, l = vt), null === l && (l = At), null !== l ? (yu = t, 
      r = yt(r, l), null === r ? (ku = t, t = r) : t = r) : (ku = t, t = vt)) : (ku = t, 
      t = vt), t;
    }
    function a() {
      var n, t, r, l, u;
      if (n = ku, t = s(), null === t && (t = At), null !== t) if (r = ku, Ru++, l = h(), 
      Ru--, null === l ? r = At : (ku = r, r = vt), null !== r) {
        for (l = [], u = p(), null === u && (u = i()); null !== u; ) l.push(u), u = p(), 
        null === u && (u = i());
        null !== l ? (u = f(), null === u && (u = At), null !== u ? (yu = n, t = wt(t, l, u), 
        null === t ? (ku = n, n = t) : n = t) : (ku = n, n = vt)) : (ku = n, n = vt);
      } else ku = n, n = vt; else ku = n, n = vt;
      return n;
    }
    function i() {
      var n;
      return n = g(), null === n && (n = S(), null === n && (n = E())), n;
    }
    function s() {
      var t, r;
      return t = ku, 94 === n.charCodeAt(ku) ? (r = Tt, ku++) : (r = null, 0 === Ru && e(gt)), 
      null !== r && (yu = t, r = xt()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function f() {
      var t, r;
      return t = ku, 36 === n.charCodeAt(ku) ? (r = Rt, ku++) : (r = null, 0 === Ru && e(Gt)), 
      null !== r && (yu = t, r = mt()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function p() {
      var n, t, r;
      return n = ku, t = i(), null !== t ? (r = h(), null !== r ? (yu = n, t = Ot(t, r), 
      null === t ? (ku = n, n = t) : n = t) : (ku = n, n = vt)) : (ku = n, n = vt), n;
    }
    function h() {
      var n, t, r;
      return Ru++, n = ku, t = d(), null !== t ? (r = w(), null === r && (r = At), null !== r ? (yu = n, 
      t = jt(t, r), null === t ? (ku = n, n = t) : n = t) : (ku = n, n = vt)) : (ku = n, 
      n = vt), Ru--, null === n && (t = null, 0 === Ru && e(Qt)), n;
    }
    function d() {
      var n;
      return n = C(), null === n && (n = v(), null === n && (n = A(), null === n && (n = b(), 
      null === n && (n = k(), null === n && (n = y()))))), n;
    }
    function C() {
      var t, r, l, u, o, c;
      return t = ku, 123 === n.charCodeAt(ku) ? (r = Ft, ku++) : (r = null, 0 === Ru && e(St)), 
      null !== r ? (l = T(), null !== l ? (44 === n.charCodeAt(ku) ? (u = Ut, ku++) : (u = null, 
      0 === Ru && e(Bt)), null !== u ? (o = T(), null !== o ? (125 === n.charCodeAt(ku) ? (c = Lt, 
      ku++) : (c = null, 0 === Ru && e(Mt)), null !== c ? (yu = t, r = Et(l, o), null === r ? (ku = t, 
      t = r) : t = r) : (ku = t, t = vt)) : (ku = t, t = vt)) : (ku = t, t = vt)) : (ku = t, 
      t = vt)) : (ku = t, t = vt), t;
    }
    function v() {
      var t, r, l, u;
      return t = ku, 123 === n.charCodeAt(ku) ? (r = Ft, ku++) : (r = null, 0 === Ru && e(St)), 
      null !== r ? (l = T(), null !== l ? (n.substr(ku, 2) === Ht ? (u = Ht, ku += 2) : (u = null, 
      0 === Ru && e(zt)), null !== u ? (yu = t, r = Zt(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
      t = vt)) : (ku = t, t = vt)) : (ku = t, t = vt), t;
    }
    function A() {
      var t, r, l, u;
      return t = ku, 123 === n.charCodeAt(ku) ? (r = Ft, ku++) : (r = null, 0 === Ru && e(St)), 
      null !== r ? (l = T(), null !== l ? (125 === n.charCodeAt(ku) ? (u = Lt, ku++) : (u = null, 
      0 === Ru && e(Mt)), null !== u ? (yu = t, r = $t(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
      t = vt)) : (ku = t, t = vt)) : (ku = t, t = vt), t;
    }
    function b() {
      var t, r;
      return t = ku, 43 === n.charCodeAt(ku) ? (r = _t, ku++) : (r = null, 0 === Ru && e(qt)), 
      null !== r && (yu = t, r = Dt()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function k() {
      var t, r;
      return t = ku, 42 === n.charCodeAt(ku) ? (r = Pt, ku++) : (r = null, 0 === Ru && e(Wt)), 
      null !== r && (yu = t, r = It()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function y() {
      var t, r;
      return t = ku, 63 === n.charCodeAt(ku) ? (r = Jt, ku++) : (r = null, 0 === Ru && e(Kt)), 
      null !== r && (yu = t, r = Nt()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function w() {
      var t;
      return 63 === n.charCodeAt(ku) ? (t = Jt, ku++) : (t = null, 0 === Ru && e(Kt)), 
      t;
    }
    function T() {
      var t, r, l;
      if (t = ku, r = [], Vt.test(n.charAt(ku)) ? (l = n.charAt(ku), ku++) : (l = null, 
      0 === Ru && e(Xt)), null !== l) for (;null !== l; ) r.push(l), Vt.test(n.charAt(ku)) ? (l = n.charAt(ku), 
      ku++) : (l = null, 0 === Ru && e(Xt)); else r = vt;
      return null !== r && (yu = t, r = Yt(r)), null === r ? (ku = t, t = r) : t = r, 
      t;
    }
    function g() {
      var t, r, l, u;
      return t = ku, 40 === n.charCodeAt(ku) ? (r = nr, ku++) : (r = null, 0 === Ru && e(tr)), 
      null !== r ? (l = G(), null === l && (l = m(), null === l && (l = O(), null === l && (l = Q(), 
      null === l && (l = j(), null === l && (l = R(), null === l && (l = x())))))), null !== l ? (41 === n.charCodeAt(ku) ? (u = rr, 
      ku++) : (u = null, 0 === Ru && e(lr)), null !== u ? (yu = t, r = ur(l), null === r ? (ku = t, 
      t = r) : t = r) : (ku = t, t = vt)) : (ku = t, t = vt)) : (ku = t, t = vt), t;
    }
    function x() {
      var n, t;
      return n = ku, t = c(), null !== t && (yu = n, t = er(t)), null === t ? (ku = n, 
      n = t) : n = t, n;
    }
    function R() {
      var t, r, l;
      return t = ku, n.substr(ku, 2) === or ? (r = or, ku += 2) : (r = null, 0 === Ru && e(cr)), 
      null !== r ? (l = c(), null !== l ? (yu = t, r = ar(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
      t = vt)) : (ku = t, t = vt), t;
    }
    function G() {
      var t, r, l;
      return t = ku, n.substr(ku, 2) === ir ? (r = ir, ku += 2) : (r = null, 0 === Ru && e(sr)), 
      null !== r ? (l = c(), null !== l ? (yu = t, r = fr(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
      t = vt)) : (ku = t, t = vt), t;
    }
    function m() {
      var t, r, l;
      return t = ku, n.substr(ku, 2) === pr ? (r = pr, ku += 2) : (r = null, 0 === Ru && e(hr)), 
      null !== r ? (l = c(), null !== l ? (yu = t, r = dr(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
      t = vt)) : (ku = t, t = vt), t;
    }
    function O() {
      var t, r, l;
      return t = ku, n.substr(ku, 3) === Cr ? (r = Cr, ku += 3) : (r = null, 0 === Ru && e(vr)), 
      null !== r ? (l = c(), null !== l ? (yu = t, r = Ar(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
      t = vt)) : (ku = t, t = vt), t;
    }
    function Q() {
      var t, r, l;
      return t = ku, n.substr(ku, 3) === br ? (r = br, ku += 3) : (r = null, 0 === Ru && e(kr)), 
      null !== r ? (l = c(), null !== l ? (yu = t, r = yr(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
      t = vt)) : (ku = t, t = vt), t;
    }
    function j() {
      var t, r, l, u, o, a;
      if (t = ku, r = F(), null !== r) {
        if (l = ku, wr.test(n.charAt(ku)) ? (u = n.charAt(ku), ku++) : (u = null, 0 === Ru && e(Tr)), 
        null !== u) {
          for (o = [], gr.test(n.charAt(ku)) ? (a = n.charAt(ku), ku++) : (a = null, 0 === Ru && e(xr)); null !== a; ) o.push(a), 
          gr.test(n.charAt(ku)) ? (a = n.charAt(ku), ku++) : (a = null, 0 === Ru && e(xr));
          null !== o ? (u = [ u, o ], l = u) : (ku = l, l = vt);
        } else ku = l, l = vt;
        null !== l ? (62 === n.charCodeAt(ku) ? (u = Rr, ku++) : (u = null, 0 === Ru && e(Gr)), 
        null !== u ? (o = c(), null !== o ? (yu = t, r = mr(l, o), null === r ? (ku = t, 
        t = r) : t = r) : (ku = t, t = vt)) : (ku = t, t = vt)) : (ku = t, t = vt);
      } else ku = t, t = vt;
      return t;
    }
    function F() {
      var t;
      return n.substr(ku, 3) === Or ? (t = Or, ku += 3) : (t = null, 0 === Ru && e(Qr)), 
      null === t && (n.substr(ku, 2) === jr ? (t = jr, ku += 2) : (t = null, 0 === Ru && e(Fr))), 
      t;
    }
    function S() {
      var t, r, l, u, o;
      if (Ru++, t = ku, 91 === n.charCodeAt(ku) ? (r = Ur, ku++) : (r = null, 0 === Ru && e(Br)), 
      null !== r) if (94 === n.charCodeAt(ku) ? (l = Tt, ku++) : (l = null, 0 === Ru && e(gt)), 
      null === l && (l = At), null !== l) {
        for (u = [], o = U(), null === o && (o = B()); null !== o; ) u.push(o), o = U(), 
        null === o && (o = B());
        null !== u ? (93 === n.charCodeAt(ku) ? (o = Lr, ku++) : (o = null, 0 === Ru && e(Mr)), 
        null !== o ? (yu = t, r = Er(l, u), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
        t = vt)) : (ku = t, t = vt);
      } else ku = t, t = vt; else ku = t, t = vt;
      return Ru--, null === t && (r = null, 0 === Ru && e(Sr)), t;
    }
    function U() {
      var t, r, l, u;
      return Ru++, t = ku, r = B(), null !== r ? (45 === n.charCodeAt(ku) ? (l = zr, ku++) : (l = null, 
      0 === Ru && e(Zr)), null !== l ? (u = B(), null !== u ? (yu = t, r = $r(r, u), null === r ? (ku = t, 
      t = r) : t = r) : (ku = t, t = vt)) : (ku = t, t = vt)) : (ku = t, t = vt), Ru--, 
      null === t && (r = null, 0 === Ru && e(Hr)), t;
    }
    function B() {
      var n, t;
      return Ru++, n = M(), null === n && (n = L()), Ru--, null === n && (t = null, 0 === Ru && e(_r)), 
      n;
    }
    function L() {
      var t, r;
      return t = ku, qr.test(n.charAt(ku)) ? (r = n.charAt(ku), ku++) : (r = null, 0 === Ru && e(Dr)), 
      null !== r && (yu = t, r = Pr(r)), null === r ? (ku = t, t = r) : t = r, t;
    }
    function M() {
      var n;
      return n = $(), null === n && (n = et(), null === n && (n = J(), null === n && (n = K(), 
      null === n && (n = N(), null === n && (n = V(), null === n && (n = X(), null === n && (n = Y(), 
      null === n && (n = nt(), null === n && (n = tt(), null === n && (n = rt(), null === n && (n = lt(), 
      null === n && (n = ut(), null === n && (n = ct(), null === n && (n = at(), null === n && (n = it(), 
      null === n && (n = st(), null === n && (n = ft()))))))))))))))))), n;
    }
    function E() {
      var n;
      return n = H(), null === n && (n = Z(), null === n && (n = z())), n;
    }
    function H() {
      var t, r;
      return t = ku, 46 === n.charCodeAt(ku) ? (r = Wr, ku++) : (r = null, 0 === Ru && e(Ir)), 
      null !== r && (yu = t, r = Jr()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function z() {
      var t, r;
      return Ru++, t = ku, Nr.test(n.charAt(ku)) ? (r = n.charAt(ku), ku++) : (r = null, 
      0 === Ru && e(Vr)), null !== r && (yu = t, r = Pr(r)), null === r ? (ku = t, t = r) : t = r, 
      Ru--, null === t && (r = null, 0 === Ru && e(Kr)), t;
    }
    function Z() {
      var n;
      return n = _(), null === n && (n = I(), null === n && (n = q(), null === n && (n = D(), 
      null === n && (n = P(), null === n && (n = W(), null === n && (n = et(), null === n && (n = J(), 
      null === n && (n = K(), null === n && (n = N(), null === n && (n = V(), null === n && (n = X(), 
      null === n && (n = Y(), null === n && (n = nt(), null === n && (n = tt(), null === n && (n = rt(), 
      null === n && (n = lt(), null === n && (n = ut(), null === n && (n = ot(), null === n && (n = ct(), 
      null === n && (n = at(), null === n && (n = it(), null === n && (n = st(), null === n && (n = ft()))))))))))))))))))))))), 
      n;
    }
    function $() {
      var t, r;
      return t = ku, n.substr(ku, 2) === Xr ? (r = Xr, ku += 2) : (r = null, 0 === Ru && e(Yr)), 
      null !== r && (yu = t, r = nl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function _() {
      var t, r;
      return t = ku, n.substr(ku, 2) === Xr ? (r = Xr, ku += 2) : (r = null, 0 === Ru && e(Yr)), 
      null !== r && (yu = t, r = tl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function q() {
      var t, r;
      return t = ku, n.substr(ku, 2) === rl ? (r = rl, ku += 2) : (r = null, 0 === Ru && e(ll)), 
      null !== r && (yu = t, r = ul()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function D() {
      var t, r;
      return t = ku, n.substr(ku, 2) === el ? (r = el, ku += 2) : (r = null, 0 === Ru && e(ol)), 
      null !== r && (yu = t, r = cl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function P() {
      var t, r;
      return t = ku, n.substr(ku, 2) === al ? (r = al, ku += 2) : (r = null, 0 === Ru && e(il)), 
      null !== r && (yu = t, r = sl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function W() {
      var t, r;
      return t = ku, n.substr(ku, 2) === fl ? (r = fl, ku += 2) : (r = null, 0 === Ru && e(pl)), 
      null !== r && (yu = t, r = hl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function I() {
      var t, r;
      return t = ku, n.substr(ku, 2) === dl ? (r = dl, ku += 2) : (r = null, 0 === Ru && e(Cl)), 
      null !== r && (yu = t, r = vl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function J() {
      var t, r;
      return t = ku, n.substr(ku, 2) === Al ? (r = Al, ku += 2) : (r = null, 0 === Ru && e(bl)), 
      null !== r && (yu = t, r = kl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function K() {
      var t, r;
      return t = ku, n.substr(ku, 2) === yl ? (r = yl, ku += 2) : (r = null, 0 === Ru && e(wl)), 
      null !== r && (yu = t, r = Tl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function N() {
      var t, r;
      return t = ku, n.substr(ku, 2) === gl ? (r = gl, ku += 2) : (r = null, 0 === Ru && e(xl)), 
      null !== r && (yu = t, r = Rl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function V() {
      var t, r;
      return t = ku, n.substr(ku, 2) === Gl ? (r = Gl, ku += 2) : (r = null, 0 === Ru && e(ml)), 
      null !== r && (yu = t, r = Ol()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function X() {
      var t, r;
      return t = ku, n.substr(ku, 2) === Ql ? (r = Ql, ku += 2) : (r = null, 0 === Ru && e(jl)), 
      null !== r && (yu = t, r = Fl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function Y() {
      var t, r;
      return t = ku, n.substr(ku, 2) === Sl ? (r = Sl, ku += 2) : (r = null, 0 === Ru && e(Ul)), 
      null !== r && (yu = t, r = Bl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function nt() {
      var t, r;
      return t = ku, n.substr(ku, 2) === Ll ? (r = Ll, ku += 2) : (r = null, 0 === Ru && e(Ml)), 
      null !== r && (yu = t, r = El()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function tt() {
      var t, r;
      return t = ku, n.substr(ku, 2) === Hl ? (r = Hl, ku += 2) : (r = null, 0 === Ru && e(zl)), 
      null !== r && (yu = t, r = Zl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function rt() {
      var t, r;
      return t = ku, n.substr(ku, 2) === $l ? (r = $l, ku += 2) : (r = null, 0 === Ru && e(_l)), 
      null !== r && (yu = t, r = ql()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function lt() {
      var t, r;
      return t = ku, n.substr(ku, 2) === Dl ? (r = Dl, ku += 2) : (r = null, 0 === Ru && e(Pl)), 
      null !== r && (yu = t, r = Wl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function ut() {
      var t, r;
      return t = ku, n.substr(ku, 2) === Il ? (r = Il, ku += 2) : (r = null, 0 === Ru && e(Jl)), 
      null !== r && (yu = t, r = Kl()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function et() {
      var t, r, l;
      return t = ku, n.substr(ku, 2) === Nl ? (r = Nl, ku += 2) : (r = null, 0 === Ru && e(Vl)), 
      null !== r ? (n.length > ku ? (l = n.charAt(ku), ku++) : (l = null, 0 === Ru && e(Xl)), 
      null !== l ? (yu = t, r = Yl(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
      t = vt)) : (ku = t, t = vt), t;
    }
    function ot() {
      var t, r, l;
      return t = ku, 92 === n.charCodeAt(ku) ? (r = nu, ku++) : (r = null, 0 === Ru && e(tu)), 
      null !== r ? (ru.test(n.charAt(ku)) ? (l = n.charAt(ku), ku++) : (l = null, 0 === Ru && e(lu)), 
      null !== l ? (yu = t, r = uu(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
      t = vt)) : (ku = t, t = vt), t;
    }
    function ct() {
      var t, r, l, u;
      if (t = ku, n.substr(ku, 2) === eu ? (r = eu, ku += 2) : (r = null, 0 === Ru && e(ou)), 
      null !== r) {
        if (l = [], cu.test(n.charAt(ku)) ? (u = n.charAt(ku), ku++) : (u = null, 0 === Ru && e(au)), 
        null !== u) for (;null !== u; ) l.push(u), cu.test(n.charAt(ku)) ? (u = n.charAt(ku), 
        ku++) : (u = null, 0 === Ru && e(au)); else l = vt;
        null !== l ? (yu = t, r = iu(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
        t = vt);
      } else ku = t, t = vt;
      return t;
    }
    function at() {
      var t, r, l, u;
      if (t = ku, n.substr(ku, 2) === su ? (r = su, ku += 2) : (r = null, 0 === Ru && e(fu)), 
      null !== r) {
        if (l = [], pu.test(n.charAt(ku)) ? (u = n.charAt(ku), ku++) : (u = null, 0 === Ru && e(hu)), 
        null !== u) for (;null !== u; ) l.push(u), pu.test(n.charAt(ku)) ? (u = n.charAt(ku), 
        ku++) : (u = null, 0 === Ru && e(hu)); else l = vt;
        null !== l ? (yu = t, r = du(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
        t = vt);
      } else ku = t, t = vt;
      return t;
    }
    function it() {
      var t, r, l, u;
      if (t = ku, n.substr(ku, 2) === Cu ? (r = Cu, ku += 2) : (r = null, 0 === Ru && e(vu)), 
      null !== r) {
        if (l = [], pu.test(n.charAt(ku)) ? (u = n.charAt(ku), ku++) : (u = null, 0 === Ru && e(hu)), 
        null !== u) for (;null !== u; ) l.push(u), pu.test(n.charAt(ku)) ? (u = n.charAt(ku), 
        ku++) : (u = null, 0 === Ru && e(hu)); else l = vt;
        null !== l ? (yu = t, r = Au(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
        t = vt);
      } else ku = t, t = vt;
      return t;
    }
    function st() {
      var t, r;
      return t = ku, n.substr(ku, 2) === eu ? (r = eu, ku += 2) : (r = null, 0 === Ru && e(ou)), 
      null !== r && (yu = t, r = bu()), null === r ? (ku = t, t = r) : t = r, t;
    }
    function ft() {
      var t, r, l;
      return t = ku, 92 === n.charCodeAt(ku) ? (r = nu, ku++) : (r = null, 0 === Ru && e(tu)), 
      null !== r ? (n.length > ku ? (l = n.charAt(ku), ku++) : (l = null, 0 === Ru && e(Xl)), 
      null !== l ? (yu = t, r = Pr(l), null === r ? (ku = t, t = r) : t = r) : (ku = t, 
      t = vt)) : (ku = t, t = vt), t;
    }
    var pt, ht = arguments.length > 1 ? arguments[1] : {}, dt = {
      regexp: c
    }, Ct = c, vt = null, At = "", bt = "|", kt = '"|"', yt = function(n, t) {
      return t ? new Alternate(n, t[1]) : n;
    }, wt = function(n, t, r) {
      return new Match([ n ].concat(t).concat([ r ]));
    }, Tt = "^", gt = '"^"', xt = function() {
      return new Token("start");
    }, Rt = "$", Gt = '"$"', mt = function() {
      return new Token("end");
    }, Ot = function(n, t) {
      return new Quantified(n, t);
    }, Qt = "Quantifier", jt = function(n, t) {
      return t && (n.greedy = !1), n;
    }, Ft = "{", St = '"{"', Ut = ",", Bt = '","', Lt = "}", Mt = '"}"', Et = function(n, t) {
      return new Quantifier(n, t);
    }, Ht = ",}", zt = '",}"', Zt = function(n) {
      return new Quantifier(n, 1/0);
    }, $t = function(n) {
      return new Quantifier(n, n);
    }, _t = "+", qt = '"+"', Dt = function() {
      return new Quantifier(1, 1/0);
    }, Pt = "*", Wt = '"*"', It = function() {
      return new Quantifier(0, 1/0);
    }, Jt = "?", Kt = '"?"', Nt = function() {
      return new Quantifier(0, 1);
    }, Vt = /^[0-9]/, Xt = "[0-9]", Yt = function(n) {
      return +n.join("");
    }, nr = "(", tr = '"("', rr = ")", lr = '")"', ur = function(n) {
      return n;
    }, er = function(n) {
      return new CaptureGroup(n);
    }, or = "?:", cr = '"?:"', ar = function(n) {
      return new Group("non-capture-group", n);
    }, ir = "?=", sr = '"?="', fr = function(n) {
      return new Group("positive-lookahead", n);
    }, pr = "?!", hr = '"?!"', dr = function(n) {
      return new Group("negative-lookahead", n);
    }, Cr = "?<=", vr = '"?<="', Ar = function(n) {
      return new Group("positive-lookbehind", n);
    }, br = "?<!", kr = '"?<!"', yr = function(n) {
      return new Group("negative-lookbehind", n);
    }, wr = /^[A-Za-z_]/, Tr = "[A-Za-z_]", gr = /^[A-Za-z0-9_]/, xr = "[A-Za-z0-9_]", Rr = ">", Gr = '">"', mr = function(n, t) {
      return new CaptureGroup(t, n);
    }, Or = "?P<", Qr = '"?P<"', jr = "?<", Fr = '"?<"', Sr = "CharacterSet", Ur = "[", Br = '"["', Lr = "]", Mr = '"]"', Er = function(n, t) {
      return new CharSet(!!n, t);
    }, Hr = "CharacterRange", zr = "-", Zr = '"-"', $r = function(n, t) {
      return new CharacterRange(n, t);
    }, _r = "Character", qr = /^[^\\\]]/, Dr = "[^\\\\\\]]", Pr = function(n) {
      return new Literal(n);
    }, Wr = ".", Ir = '"."', Jr = function() {
      return new Token("any-character");
    }, Kr = "Literal", Nr = /^[^|\\\/.[()?+*$\^]/, Vr = "[^|\\\\\\/.[()?+*$\\^]", Xr = "\\b", Yr = '"\\\\b"', nl = function() {
      return new Token("backspace");
    }, tl = function() {
      return new Token("word-boundary");
    }, rl = "\\A", ll = '"\\\\A"', ul = function() {
      return new Token("begin-of-string");
    }, el = "\\Z", ol = '"\\\\Z"', cl = function() {
      return new Token("end-of-string-before-nl");
    }, al = "\\z", il = '"\\\\z"', sl = function() {
      return new Token("end-of-string");
    }, fl = "\\G", pl = '"\\\\G"', hl = function() {
      return new Token("match-start-position");
    }, dl = "\\B", Cl = '"\\\\B"', vl = function() {
      return new Token("non-word-boundary");
    }, Al = "\\d", bl = '"\\\\d"', kl = function() {
      return new Token("digit");
    }, yl = "\\D", wl = '"\\\\D"', Tl = function() {
      return new Token("non-digit");
    }, gl = "\\f", xl = '"\\\\f"', Rl = function() {
      return new Token("form-feed");
    }, Gl = "\\n", ml = '"\\\\n"', Ol = function() {
      return new Token("line-feed");
    }, Ql = "\\r", jl = '"\\\\r"', Fl = function() {
      return new Token("carriage-return");
    }, Sl = "\\s", Ul = '"\\\\s"', Bl = function() {
      return new Token("white-space");
    }, Ll = "\\S", Ml = '"\\\\S"', El = function() {
      return new Token("non-white-space");
    }, Hl = "\\t", zl = '"\\\\t"', Zl = function() {
      return new Token("tab");
    }, $l = "\\v", _l = '"\\\\v"', ql = function() {
      return new Token("vertical-tab");
    }, Dl = "\\w", Pl = '"\\\\w"', Wl = function() {
      return new Token("word");
    }, Il = "\\W", Jl = '"\\\\W"', Kl = function() {
      return new Token("non-word");
    }, Nl = "\\c", Vl = '"\\\\c"', Xl = "any character", Yl = function(n) {
      return new ControlCharacter(n);
    }, nu = "\\", tu = '"\\\\"', ru = /^[1-9]/, lu = "[1-9]", uu = function(n) {
      return new BackReference(n);
    }, eu = "\\0", ou = '"\\\\0"', cu = /^[0-7]/, au = "[0-7]", iu = function(n) {
      return new Octal(n.join(""));
    }, su = "\\x", fu = '"\\\\x"', pu = /^[0-9a-fA-F]/, hu = "[0-9a-fA-F]", du = function(n) {
      return new Hex(n.join(""));
    }, Cu = "\\u", vu = '"\\\\u"', Au = function(n) {
      return new Unicode(n.join(""));
    }, bu = function() {
      return new Token("null-character");
    }, ku = 0, yu = 0, wu = 0, Tu = {
      line: 1,
      column: 1,
      seenCR: !1
    }, gu = 0, xu = [], Ru = 0;
    if ("startRule" in ht) {
      if (!(ht.startRule in dt)) throw new Error("Can't start parsing from rule \"" + ht.startRule + '".');
      Ct = dt[ht.startRule];
    }
    if (Token.offset = l, Token.text = r, pt = Ct(), null !== pt && ku === n.length) return pt;
    throw o(xu), yu = Math.max(ku, gu), new t(xu, yu < n.length ? n.charAt(yu) : null, yu, u(yu).line, u(yu).column);
  }
  return n(t, Error), {
    SyntaxError: t,
    parse: r
  };
}(), index = 1, cgs = {};

exports = module.exports = parse, exports.Token = Token, exports.Alternate = Alternate, 
Alternate.prototype = Object.create(Token.prototype), Alternate.prototype.constructor = Alternate, 
exports.Match = Match, Match.prototype = Object.create(Token.prototype), Match.prototype.constructor = Match, 
exports.Group = Group, Group.prototype = Object.create(Token.prototype), Group.prototype.constructor = Group, 
exports.CaptureGroup = CaptureGroup, CaptureGroup.prototype = Object.create(Group.prototype), 
CaptureGroup.prototype.constructor = CaptureGroup, exports.Quantified = Quantified, 
Quantified.prototype = Object.create(Token.prototype), Quantified.prototype.constructor = Quantified, 
exports.Quantifier = Quantifier, Quantifier.prototype = Object.create(Token.prototype), 
Quantifier.prototype.constructor = Quantifier, exports.CharSet = CharSet, CharSet.prototype = Object.create(Token.prototype), 
CharSet.prototype.constructor = CharSet, exports.CharacterRange = CharacterRange, 
CharacterRange.prototype = Object.create(Token.prototype), CharacterRange.prototype.constructor = CharacterRange, 
exports.Literal = Literal, Literal.prototype = Object.create(Token.prototype), Literal.prototype.constructor = Literal, 
exports.Unicode = Unicode, Unicode.prototype = Object.create(Token.prototype), Unicode.prototype.constructor = Unicode, 
exports.Hex = Hex, Hex.prototype = Object.create(Token.prototype), Hex.prototype.constructor = Hex, 
exports.Octal = Octal, Octal.prototype = Object.create(Token.prototype), Octal.prototype.constructor = Octal, 
exports.BackReference = BackReference, BackReference.prototype = Object.create(Token.prototype), 
BackReference.prototype.constructor = BackReference, exports.ControlCharacter = ControlCharacter, 
ControlCharacter.prototype = Object.create(Token.prototype), ControlCharacter.prototype.constructor = ControlCharacter;