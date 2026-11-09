import struct, sys

def decode(path):
    d=open(path,'rb').read()
    magic=d[:4].decode(); dic=d[16:16+256]
    entries=[]; p=0x110
    while True:
        a,b,c=struct.unpack('>III',d[p:p+12])
        if a==0: break
        entries.append((a,b,c)); p+=12
    out_all=[]
    for (csize,usize,off) in entries:
        src=d[off:off+csize]
        pos=0; bitbuf=0; nbits=0
        def getbit():
            nonlocal pos,bitbuf,nbits
            if nbits==0:
                bitbuf=src[pos]; pos+=1; nbits=8
            nbits-=1
            return (bitbuf>>nbits)&1
        def getcode():
            n=0
            while getbit()==1: n+=1
            v=(1<<(n+1))-2
            w=0
            for _ in range(n+1): w=(w<<1)|getbit()
            return v+w
        out=bytearray()
        while len(out)<usize:
            c=getcode()
            if c<0x100:
                out.append(dic[c])
            else:
                ln=getcode()+3
                dist=c-0x100
                st=len(out)-dist
                for i in range(ln):
                    out.append(out[st+i])
        out_all.append(bytes(out))
    return magic,entries,out_all

if __name__=='__main__':
    for f in sys.argv[1:]:
        try:
            m,e,o=decode(f)
            print(f, m, 'chunks:',len(e), 'sizes:',[len(x) for x in o], 'expected:',[b for _,b,_ in e])
        except Exception as ex:
            print(f,'FAIL',ex)
