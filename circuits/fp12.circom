pragma circom 2.0.3;

include "bigint.circom";
include "field_elements_func.circom";
include "fp.circom";
include "fp2.circom";
include "bls12_381_func.circom";

template Fp12FrobeniusMap(n, k, power){
    signal input in[6][2][k];
    signal output out[6][2][k];

    var p[50] = get_BLS12_381_prime(n, k);
    var FP12_FROBENIUS_COEFFICIENTS[12][6][2][20] = get_Fp12_frobenius(n, k);
    var pow = power % 12;
 
    component in_frob[6]; 
 
    // multiply in_frob[i] by FP12_FROBENIUS_COEFFICIENTS[pow][i] 
    // if pow is even, then FP12_FROBENIUS_COEFFICIENTS[pow][i] is in Fp instead of Fp2, so can optimize 
    component mult_odd[6];
    component mult_even[6][2];
    if( (pow % 2) == 0 ){
        for(var j=0; j<k; j++){
            out[0][0][j] <== in[0][0][j];
            out[0][1][j] <== in[0][1][j];
        } 
        for(var i=1; i<6; i++){
            mult_even[i][0] = FpMultiply(n, k, p);
            mult_even[i][1] = FpMultiply(n, k, p);
            for(var j=0; j<k; j++){
                mult_even[i][0].a[j] <== in[i][0][j];
                mult_even[i][1].a[j] <== in[i][1][j];

                mult_even[i][0].b[j] <== FP12_FROBENIUS_COEFFICIENTS[pow][i][0][j];
                mult_even[i][1].b[j] <== FP12_FROBENIUS_COEFFICIENTS[pow][i][0][j];
            }
            for(var j=0; j<k; j++){
                out[i][0][j] <== mult_even[i][0].out[j];
                out[i][1][j] <== mult_even[i][1].out[j];
            }
        }
    }else{
        // apply Frob to coefficients first
        for(var i=0; i<6; i++){
            in_frob[i] = Fp2FrobeniusMap(n, k, pow, p); 
            for(var j=0; j<k; j++){
                in_frob[i].in[0][j] <== in[i][0][j];
                in_frob[i].in[1][j] <== in[i][1][j];
            }
        }
        for(var j=0; j<k; j++){
            out[0][0][j] <== in_frob[0].out[0][j];
            out[0][1][j] <== in_frob[0].out[1][j];
        } 
        for(var i=1; i<6; i++){
            mult_odd[i] = Fp2Multiply(n, k, p);
            for(var j=0; j<k; j++){
                for(var eps=0; eps<2; eps++){
                    mult_odd[i].a[eps][j] <== in_frob[i].out[eps][j];
                    mult_odd[i].b[eps][j] <== FP12_FROBENIUS_COEFFICIENTS[pow][i][eps][j];
                }
            }
            for(var j=0; j<k; j++){
                out[i][0][j] <== mult_odd[i].out[0][j];
                out[i][1][j] <== mult_odd[i].out[1][j];
            }
        }
    }
}

template Fp12Add(n, k, p) {
    signal input a[6][2][k];
    signal input b[6][2][k];
    signal output out[6][2][k];
    component adders[6][2];
    for (var i = 0; i < 6; i ++) {
        for (var j = 0; j < 2; j ++) {
            adders[i][j] = FpAdd(n,k, p);
            for (var m = 0; m < k; m ++) {
                adders[i][j].a[m] <== a[i][j][m];
                adders[i][j].b[m] <== b[i][j][m];
                adders[i][j].p[m] <== p[m];
            }
            for (var m = 0; m < k; m ++) {
                out[i][j][m] <== adders[i][j].out[m];
            }
        }
    }
}

// a is k array representing element a of Fp allowing negative registers
// b is 6 x 2 x k array representing element b0 + b1 u of Fp12 allowing negative registers
//      where b_i = b[][i][] is 6 x k array
// out is a*b in Fp12 as 6 x 2 x (2k-1) array
// m_out is the expected max number of bits in the output registers
template SignedFp12ScalarMultiplyNoCarry(n, k, m_out){
    signal input a[k];
    signal input b[6][2][k];
    signal output out[6][2][2*k-1];

    component ab[6][2]; 
    for(var i=0; i<6; i++)for(var j=0; j<2; j++){
        ab[i][j] = BigMultShortLong(n, k, m_out); // 2k-1 registers 

        for(var idx=0; idx<k; idx++){
            ab[i][j].a[idx] <== a[idx];
            ab[i][j].b[idx] <== b[i][j][idx]; 
        } 
    }
    
    for(var i=0; i<6; i++)for(var j=0; j<2; j++)for(var idx=0; idx<2*k-1; idx++)
        out[i][j][idx] <== ab[i][j].out[idx];
}

// m_out is the expected max number of bits in the output registers
template SignedFp12ScalarMultiplyNoCarryUnequal(n, ka, kb, m_out){
    signal input a[ka];
    signal input b[6][2][kb];
    signal output out[6][2][ka+kb-1];

    component ab[6][2]; 
    for(var i=0; i<6; i++)for(var j=0; j<2; j++){
        ab[i][j] = BigMultShortLongUnequal(n, ka, kb, m_out); // 2k-1 registers 

        for(var idx=0; idx<ka; idx++)
            ab[i][j].a[idx] <== a[idx];
        for(var idx=0; idx<kb; idx++)
            ab[i][j].b[idx] <== b[i][j][idx]; 
    }
    
    for(var i=0; i<6; i++)for(var j=0; j<2; j++)for(var idx=0; idx<ka+kb-1; idx++)
        out[i][j][idx] <== ab[i][j].out[idx];
}

// a is 2 x k array representing element a of Fp2 allowing negative registers
// b is 6 x 2 x k array representing element b0 + b1 u of Fp12 allowing negative registers
//      where b_i = b[][i][] is 6 x k array
// out is a*b in Fp12 as 6 x 2 x (2k-1) array
// m_out is the expected max number of bits in the output registers
template SignedFp12Fp2MultiplyNoCarry(n, k, m_out){
    signal input a[2][k];
    signal input b[6][2][k];
    signal output out[6][2][2*k-1];

    component ab[6][2];
    component abi[6][2];
    for(var i=0; i<6; i++)for(var j=0; j<2; j++){
        ab[i][j] = BigMultShortLong(n, k, m_out); // 2k-1 registers
        abi[i][j] = BigMultShortLong(n, k, m_out); // 2k-1 registers 

        for(var idx=0; idx<k; idx++){
            ab[i][j].a[idx] <== a[0][idx];
            ab[i][j].b[idx] <== b[i][j][idx]; 
        } 
        for(var idx=0; idx<k; idx++){
            abi[i][j].a[idx] <== a[1][idx];
            abi[i][j].b[idx] <== b[i][j][idx]; 
        }
    }
    
    for(var i=0; i<6; i++)for(var idx=0; idx<2*k-1; idx++) {
        out[i][0][idx] <== ab[i][0].out[idx] - abi[i][1].out[idx];
        out[i][1][idx] <== abi[i][0].out[idx] + ab[i][1].out[idx];
    }
}

// m_out is the expected max number of bits in the output registers
template SignedFp12Fp2MultiplyNoCarryUnequal(n, ka, kb, m_out){
    signal input a[2][ka];
    signal input b[6][2][kb];
    signal output out[6][2][ka+kb-1];

    component ab[6][2];
    component abi[6][2];
    for(var i=0; i<6; i++)for(var j=0; j<2; j++){
        ab[i][j] = BigMultShortLongUnequal(n, ka, kb, m_out); // 2k-1 registers
        abi[i][j] = BigMultShortLongUnequal(n, ka, kb, m_out); // 2k-1 registers 

        for(var idx=0; idx<ka; idx++){
            ab[i][j].a[idx] <== a[0][idx];
            abi[i][j].a[idx] <== a[1][idx];
        }
        for(var idx=0; idx<kb; idx++){
            ab[i][j].b[idx] <== b[i][j][idx];
            abi[i][j].b[idx] <== b[i][j][idx];
        }
    }
    
    for(var i=0; i<6; i++)for(var idx=0; idx<ka+kb-1; idx++){
        out[i][0][idx] <== ab[i][0].out[idx] - abi[i][1].out[idx];
        out[i][1][idx] <== abi[i][0].out[idx] + ab[i][1].out[idx];
    }
}

// we first write a = a0 + a1 u, b = b0 + b1 u for ai, bi being:
//     * length 6 vectors with ka, kb registers in (-B_a, B_a) and (-B_b, B_b)
// ab = (a0 b0 - a1 b1 ) + (a0 b1 + a1 b0) u
// set X = a0 b0 + a2 b2 + a1 b3 + a3 b1, Z = a0 b2 + a2 b0 + a1 b1 + a3 b3
//     Y = a0 b1 + a2 b3 + a1 b0 + a3 b2, W = a0 b3 + a2 b1 + a1 b2 + a3 b0 u
// Assume w^6 = XI0 + u 
// The real and imaginary parts are
//     * length 6 vectors with ka+kb-1 registers abs val < B_a * B_b * 6 * min(ka, kb) * (2+XI0)
// m_out is the expected max number of bits in the output registers
template SignedFp12MultiplyNoCarryUnequal(n, ka, kb, m_out){
    var l = 6;
    var XI0 = 1;
    signal input a[l][2][ka];
    signal input b[l][2][kb];
    signal output out[l][2][ka + kb -1];

    component a0b0 = BigMultShortLong2DUnequal(n, ka, kb, l, l);
    component a0b1 = BigMultShortLong2DUnequal(n, ka, kb, l, l);
    component a1b0 = BigMultShortLong2DUnequal(n, ka, kb, l, l);
    component a1b1 = BigMultShortLong2DUnequal(n, ka, kb, l, l);
    
    for (var i = 0; i < l; i ++) {
        for (var j = 0; j < ka; j ++) {
            a0b0.a[i][j] <== a[i][0][j];
            a0b1.a[i][j] <== a[i][0][j];

            a1b0.a[i][j] <== a[i][1][j];
            a1b1.a[i][j] <== a[i][1][j];
        }
        for (var j = 0; j < kb; j ++) {
            a0b0.b[i][j] <== b[i][0][j];
            a1b0.b[i][j] <== b[i][0][j];

            a0b1.b[i][j] <== b[i][1][j];
            a1b1.b[i][j] <== b[i][1][j];
        }
	}
    

    signal X[2 * l - 1][2][ka + kb - 1];
    for (var i = 0; i < 2 * l - 1; i++) {
        for (var j = 0; j < ka + kb - 1; j++) {
            X[i][0][j] <== a0b0.out[i][j] - a1b1.out[i][j];
            X[i][1][j] <== a0b1.out[i][j] + a1b0.out[i][j];
        }
    }

    for (var i = 0; i < l; i++)for (var j = 0; j < ka + kb - 1; j++) {
        if (i < l - 1) {
            out[i][0][j] <== X[i][0][j] + X[l + i][0][j]*XI0 - X[l + i][1][j];
            out[i][1][j] <== X[i][1][j] + X[l + i][0][j]     + X[l + i][1][j];
        } else {
            out[i][0][j] <== X[i][0][j];
            out[i][1][j] <== X[i][1][j];
        }
    }
}

template SignedFp12MultiplyNoCarry(n, k, m_out){
    var l = 6;
    signal input a[l][2][k];
    signal input b[l][2][k];
    signal output out[l][2][2*k-1];
    
    component mult = SignedFp12MultiplyNoCarryUnequal(n, k, k, m_out);
    for(var i=0; i<l; i++)for(var j=0; j<2; j++)for(var idx=0; idx<k; idx++){
        mult.a[i][j][idx] <== a[i][j][idx];
        mult.b[i][j][idx] <== b[i][j][idx];
    }
    for(var i=0; i<l; i++)for(var j=0; j<2; j++)for(var idx=0; idx<2*k-1; idx++)
        out[i][j][idx] <== mult.out[i][j][idx]; 
}

// m_out is the expected max number of bits in the output registers
template Fp12Compress(n, k, m, p, m_out){
    var l = 6;
    signal input in[l][2][k+m];
    signal output out[l][2][k];

    component reduce[l][2];
    for (var i = 0; i < l; i++)for (var j = 0; j < 2; j++){
        reduce[i][j] = PrimeReduce(n, k, m, p, m_out);
        for (var idx = 0; idx < k + m; idx++) 
            reduce[i][j].in[idx] <== in[i][j][idx];
    }

    for (var i = 0; i < l; i++)for (var j = 0; j < 2; j++)for (var idx = 0; idx < k; idx++) 
        out[i][j][idx] <== reduce[i][j].out[idx];
}

// Input is same as for Fp12MultiplyNoCarry
// Our answer is the prime reduction of output of Fp12MultiplyNoCarry to
//     * length 6 vectors with k registers in [0, B_a * B_b * 2^n * 6*(2+XI0) * k^2 )
// p is length k
// m_in is the expected max number of bits in the input registers (necessary for some intermediate overflow validation)
// m_out is the expected max number of bits in the output registers
template SignedFp12MultiplyNoCarryCompress(n, k, p, m_in, m_out) {
    var l = 6;
    var XI0 = 1;
    signal input a[l][2][k];
    signal input b[l][2][k];
    signal output out[l][2][k];

    var LOGK1 = log_ceil(6*k*(2+XI0));
    component nocarry = SignedFp12MultiplyNoCarry(n, k, 2*m_in + LOGK1);
    for (var i = 0; i < l; i ++)for(var j=0; j<2; j++)for(var idx=0; idx<k; idx++){ 
        nocarry.a[i][j][idx] <== a[i][j][idx];
        nocarry.b[i][j][idx] <== b[i][j][idx];
    }

    component reduce = Fp12Compress(n, k, k-1, p, m_out);
    for (var i = 0; i < l; i++)for (var j = 0; j < 2; j++)
        for (var idx = 0; idx < 2 * k - 1; idx++) 
            reduce.in[i][j][idx] <== nocarry.out[i][j][idx];

    for (var i = 0; i < l; i++)for (var j = 0; j < 2; j++)
        for (var idx = 0; idx < k; idx++) 
            out[i][j][idx] <== reduce.out[i][j][idx];
}

// solve for: in = X * p + out
// X has Ceil( overflow / n ) registers, lying in [-2^n, 2^n)
// assume in has registers in [0, 2^overflow)
template SignedFp12CarryModP(n, k, overflow, p) {
    var l = 6;
    var m = (overflow + n - 1) \ n;
    signal input in[l][2][k];
    signal output X[l][2][m];
    signal output out[l][2][k];

    assert( overflow < 251 );

    component carry[l][2];
    for(var i=0; i<l; i++)for(var j=0; j<2; j++){
        carry[i][j] = SignedFpCarryModP(n, k, overflow, p);
        for(var idx=0; idx<k; idx++)
            carry[i][j].in[idx] <== in[i][j][idx];
        for(var idx=0; idx<m; idx++)
            X[i][j][idx] <== carry[i][j].X[idx];
        for(var idx=0; idx<k; idx++)
            out[i][j][idx] <== carry[i][j].out[idx];
    }
}


// version of Fp12Multiply that uses the prime reduction trick
// takes longer to compile
// assumes p has k registers with kth register nonzero
template Fp12Multiply(n, k, p) {
    var l = 6;
    var XI0 = 1;
    signal input a[l][2][k];
    signal input b[l][2][k];
    
    signal output out[l][2][k];

    var LOGK2 = log_ceil(6*k*k*(2+XI0)); 
    component no_carry = SignedFp12MultiplyNoCarryCompress(n, k, p, n, 3*n + LOGK2);
    // registers abs val < 2^{3n} * 6*(2 + XI0) * k^2 )
    for (var i = 0; i < l; i++)for(var j = 0; j < 2; j++){
        for (var idx = 0; idx < k; idx++) {
            no_carry.a[i][j][idx] <== a[i][j][idx];
            no_carry.b[i][j][idx] <== b[i][j][idx];
        }
    }
    component carry_mod;
    carry_mod = SignedFp12CarryModP(n, k, 3*n + LOGK2, p);
    for (var i = 0; i < l; i++)for (var j = 0; j < 2; j++)
        for (var idx = 0; idx < k; idx++)
		    carry_mod.in[i][j][idx] <== no_carry.out[i][j][idx];
        
    
    for (var i = 0; i < l; i++)for (var j = 0; j < 2; j++)
        for (var idx = 0; idx < k; idx++)
            out[i][j][idx] <== carry_mod.out[i][j][idx];
}

// unoptimized squaring, just takes two elements of Fp12 and multiplies them
template Fp12Square(n, k, p) {
    signal input in[6][2][k];
    signal output out[6][2][k];

    // for now just use plain multiplication, this can be optimized later
    component square = Fp12Multiply(n, k, p);
    for(var i=0; i<6; i++)for(var j=0; j<k; j++){
        square.a[i][0][j] <== in[i][0][j];
        square.a[i][1][j] <== in[i][1][j];
    
        square.b[i][0][j] <== in[i][0][j];
        square.b[i][1][j] <== in[i][1][j];
    }

    for(var i=0; i<6; i++)for(var j=0; j<k; j++){
        out[i][0][j] <== square.out[i][0][j];
        out[i][1][j] <== square.out[i][1][j];
    }
}


// not actually a relevant circuit - this only exists to test find_Fp6_inverse
template Fp6Invert(n, k, p) {
    signal input a0[2][k];
    signal input a1[2][k];
    signal input a2[2][k];
    var out[6][2][50] = find_Fp6_inverse(n, k, p, a0, a1, a2);
    signal output real_out[6][2][k];
    for (var i = 0; i < 6; i++) {
        for (var j = 0; j < 2; j ++) {
            for (var idx = 0; idx < k; idx++) {
                real_out[i][j][idx] <-- out[i][j][idx];
            }
        }
    }
}

// Call find_Fp12_inverse to compute inverse
// Then check out * in = 1, out is an array of shorts
template Fp12Invert(n, k, p){
    signal input in[6][2][k];
    signal output out[6][2][k];

    var inverse[6][2][50] = find_Fp12_inverse(n, k, p, in); // 6 x 2 x 50, only 6 x 2 x k relevant
    for (var i = 0; i < 6; i ++) {
        for (var j = 0; j < 2; j ++) {
            for (var m = 0; m < k; m ++) {
                out[i][j][m] <-- inverse[i][j][m];
            }
        }
    }

    component outRangeChecks[6][2][k];
    for(var i=0; i<6; i++) for(var j=0; j<2; j++) for(var m=0; m<k; m++) {
        outRangeChecks[i][j][m] = Num2Bits(n);
        outRangeChecks[i][j][m].in <== out[i][j][m];
    }

    component in_out = Fp12Multiply(n, k, p);
    for(var i=0; i<6; i++) for(var j=0; j<2; j++) for(var m=0; m<k; m++) {
        in_out.a[i][j][m] <== in[i][j][m];
        in_out.b[i][j][m] <== out[i][j][m];
    }

    for(var i=0; i<6; i++)for(var j=0; j<2; j++) for(var m = 0; m < k; m ++) {
        if(i == 0 && j == 0 && m == 0)
            in_out.out[i][j][m] === 1;
        else
            in_out.out[i][j][m] === 0;
    }
}

// input is an element of Fp12 
// output is input raised to the e-th power
// use the square and multiply method
// assume 0 < e < 2^254
template Fp12Exp(n, k, e, p) {
    assert( e > 0 );

    signal input in[6][2][k];
    signal output out[6][2][k];

    var temp = e;
    var BITLENGTH;
    for(var i=0; i<254; i++){
        if( temp != 0 )
            BITLENGTH = i; 
        temp = temp>>1;
    }
    BITLENGTH++;
    component pow2[BITLENGTH]; // pow2[i] = in^{2^i} 
    component mult[BITLENGTH];

    signal first[6][2][k];
    var curid = 0;

    for(var i=0; i<BITLENGTH; i++){
        // compute pow2[i] = pow2[i-1]**2
        if( i > 0 ){ // pow2[0] is never defined since there is no squaring involved
            pow2[i] = Fp12Square(n, k, p);
            for(var j=0; j<k; j++) pow2[i].p[j] <== p[j];
            if( i == 1 ){
                for(var id=0; id<6; id++)for(var eps=0; eps<2; eps++)for(var j=0; j<k; j++)
                    pow2[i].in[id][eps][j] <== in[id][eps][j];
            }else{
                for(var id=0; id<6; id++)for(var eps=0; eps<2; eps++)for(var j=0; j<k; j++)
                    pow2[i].in[id][eps][j] <== pow2[i-1].out[id][eps][j];
            }
        }
        if( ((e >> i) & 1) == 1 ){
            if(curid == 0){ // this is the least significant bit
                if( i == 0 ){
                    for(var id=0; id<6; id++)for(var eps=0; eps<2; eps++)for(var j=0; j<k; j++)
                        first[id][eps][j] <== in[id][eps][j];
                }else{
                    for(var id=0; id<6; id++)for(var eps=0; eps<2; eps++)for(var j=0; j<k; j++)
                        first[id][eps][j] <== pow2[i].out[id][eps][j];
                }
            }else{
                // multiply what we already have with pow2[i]
                mult[curid] = Fp12Multiply(n, k, p); 
                for(var id=0; id<6; id++)for(var eps=0; eps<2; eps++)for(var j=0; j<k; j++)
                    mult[curid].a[id][eps][j] <== pow2[i].out[id][eps][j];
                if(curid == 1){
                    for(var id=0; id<6; id++)for(var eps=0; eps<2; eps++)for(var j=0; j<k; j++)
                        mult[curid].b[id][eps][j] <== first[id][eps][j];
                }else{
                    for(var id=0; id<6; id++)for(var eps=0; eps<2; eps++)for(var j=0; j<k; j++)
                        mult[curid].b[id][eps][j] <== mult[curid-1].out[id][eps][j];
                }
            } 
            curid++; 
        }
    }
    curid--;
    if(curid == 0){
        for(var id=0; id<6; id++)for(var eps=0; eps<2; eps++)for(var j=0; j<k; j++)
            out[id][eps][j] <== first[id][eps][j];
    }else{
        for(var id=0; id<6; id++)for(var eps=0; eps<2; eps++)for(var j=0; j<k; j++)
            out[id][eps][j] <== mult[curid].out[id][eps][j];
    }
}

