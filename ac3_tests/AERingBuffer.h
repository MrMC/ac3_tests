#ifndef ringbuffer_h
#define ringbuffer_h

#ifdef __cplusplus
class AERingBuffer
{
  public:
    AERingBuffer();
    AERingBuffer(unsigned int size, unsigned int planes = 1);
   ~AERingBuffer();
    
    bool Create(int size, unsigned int planes = 1);
    void Reset();
    int Write(unsigned char *src, unsigned int size, unsigned int plane = 0);
    int Read(unsigned char *dest, unsigned int size, unsigned int plane = 0);
    void Dump();
    unsigned int GetWriteSize();
    unsigned int GetReadSize();
    unsigned int GetMaxSize();
    unsigned int NumPlanes() const;
  private:
  void WriteFinished(unsigned int size);
  void ReadFinished(unsigned int size);


  unsigned int m_iReadPos;
  unsigned int m_iWritePos;
  unsigned int m_iRead;
  unsigned int m_iWritten;
  unsigned int m_iSize;
  unsigned int m_planes;
  unsigned char **m_Buffer;
};
#endif

#endif /* ringbuffer_h */
