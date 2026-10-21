// =============================================================================
// NA POINT CLOUD VIEWER - NATIVE ENGINE - LAZ CONVERTER - RECORD WRITER
// =============================================================================
//
// FILE       : Na__PointCloudViewer__NativeEngine__LazRecord__.cpp
// PURPOSE    : Turns a decoded laszip_point back into LAS record bytes with
//              LASzip's OWN raw item writers - the classes its uncompressed
//              writer uses - in the item order of each point format
//              (laszip.cpp, LASzip::setup). No field is converted here.
//
// =============================================================================

#include "Na__PointCloudViewer__NativeEngine__LazConvert__.hpp"
#include "Na__PointCloudViewer__NativeEngine__LasFile__.hpp"

#include "laszip_api.h"
// LASzip's internal headers are third-party and not /W4-clean (unused
// parameters, a shadowed member); they stay unmodified, so mute them here.
#pragma warning(push, 0)
#include "bytestreamout.hpp"
#include "laswriteitemraw.hpp"
#pragma warning(pop)

#include <cstring>
#include <vector>

namespace {

    // A ByteStreamOut over one record's bytes (the items only ever putBytes).
    class Na__RecordStream : public ByteStreamOut {
    public:
        void Begin(uint8_t* out, uint32_t capacity) { m_out = out; m_capacity = capacity; m_used = 0; m_ok = true; }
        uint32_t Used() const { return m_used; }
        bool Ok() const { return m_ok; }

        BOOL putByte(U8 byte) override { return this->putBytes(&byte, 1); }
        BOOL putBytes(const U8* bytes, U32 num_bytes) override {
            if (!m_out || m_used + num_bytes > m_capacity) { m_ok = false; return FALSE; }
            std::memcpy(m_out + m_used, bytes, num_bytes);
            m_used += num_bytes;
            return TRUE;
        }
        BOOL put16bitsLE(const U8* bytes) override { return this->putBytes(bytes, 2); }
        BOOL put32bitsLE(const U8* bytes) override { return this->putBytes(bytes, 4); }
        BOOL put64bitsLE(const U8* bytes) override { return this->putBytes(bytes, 8); }
        BOOL put16bitsBE(const U8*) override { m_ok = false; return FALSE; }
        BOOL put32bitsBE(const U8*) override { m_ok = false; return FALSE; }
        BOOL put64bitsBE(const U8*) override { m_ok = false; return FALSE; }
        BOOL isSeekable() const override { return FALSE; }
        I64 tell() const override { return m_used; }
        BOOL seek(const I64) override { return FALSE; }
        BOOL seekEnd() override { return FALSE; }

    private:
        uint8_t* m_out = nullptr;
        uint32_t m_capacity = 0;
        uint32_t m_used = 0;
        bool     m_ok = true;
    };

    enum Na__ItemKind { NA_POINT10, NA_POINT14, NA_GPSTIME, NA_RGB, NA_RGBNIR, NA_WAVEPACKET, NA_BYTES };

} // namespace

struct Na__LazRecordWriter::Impl {
    Na__RecordStream             stream;
    std::vector<LASwriteItemRaw*> items;
    std::vector<const U8*>        sources;
    uint32_t                      record_length = 0;

    ~Impl() { for (LASwriteItemRaw* item : items) delete item; }
};

Na__LazRecordWriter::Na__LazRecordWriter() : m_impl(new Impl()) {}
Na__LazRecordWriter::~Na__LazRecordWriter() { delete m_impl; }

bool Na__LazRecordWriter::Setup(int point_format, int record_length, const laszip_point* point, std::string& error) {
    const int base = Na__Las__MinRecordLength(point_format);
    if (base < 0 || record_length < base) {
        error = "Point format " + std::to_string(point_format) + " with " + std::to_string(record_length) +
                "-byte records is not a valid LAS point format.";
        return false;
    }
    // Item order per format, exactly as LASzip::setup lays them out.
    std::vector<Na__ItemKind> kinds;
    switch (point_format) {
        case 0:  kinds = { NA_POINT10 }; break;
        case 1:  kinds = { NA_POINT10, NA_GPSTIME }; break;
        case 2:  kinds = { NA_POINT10, NA_RGB }; break;
        case 3:  kinds = { NA_POINT10, NA_GPSTIME, NA_RGB }; break;
        case 4:  kinds = { NA_POINT10, NA_GPSTIME, NA_WAVEPACKET }; break;
        case 5:  kinds = { NA_POINT10, NA_GPSTIME, NA_RGB, NA_WAVEPACKET }; break;
        case 6:  kinds = { NA_POINT14 }; break;
        case 7:  kinds = { NA_POINT14, NA_RGB }; break;
        case 8:  kinds = { NA_POINT14, NA_RGBNIR }; break;
        case 9:  kinds = { NA_POINT14, NA_WAVEPACKET }; break;
        case 10: kinds = { NA_POINT14, NA_RGBNIR, NA_WAVEPACKET }; break;
        default: error = "Unknown point format " + std::to_string(point_format) + "."; return false;
    }
    const int extra = record_length - base;
    if (extra > 0) {
        if (point->num_extra_bytes != extra || !point->extra_bytes) {
            error = "LASzip reports " + std::to_string(point->num_extra_bytes) + " extra bytes per point, but the header implies " +
                    std::to_string(extra) + ".";
            return false;
        }
        kinds.push_back(NA_BYTES);
    }

    for (Na__ItemKind kind : kinds) {
        LASwriteItemRaw* item = nullptr;
        const U8* source = nullptr;
        switch (kind) {
            case NA_POINT10:     item = new LASwriteItemRaw_POINT10_LE();     source = reinterpret_cast<const U8*>(&point->X); break;
            case NA_POINT14:     item = new LASwriteItemRaw_POINT14_LE();     source = reinterpret_cast<const U8*>(&point->X); break;
            case NA_GPSTIME:     item = new LASwriteItemRaw_GPSTIME11_LE();   source = reinterpret_cast<const U8*>(&point->gps_time); break;
            case NA_RGB:         item = new LASwriteItemRaw_RGB12_LE();       source = reinterpret_cast<const U8*>(point->rgb); break;
            case NA_RGBNIR:      item = new LASwriteItemRaw_RGBNIR14_LE();    source = reinterpret_cast<const U8*>(point->rgb); break;
            case NA_WAVEPACKET:  item = new LASwriteItemRaw_WAVEPACKET13_LE(); source = point->wave_packet; break;
            case NA_BYTES:       item = new LASwriteItemRaw_BYTE(static_cast<U32>(extra)); source = point->extra_bytes; break;
        }
        item->init(&m_impl->stream);
        m_impl->items.push_back(item);
        m_impl->sources.push_back(source);
    }
    m_impl->record_length = static_cast<uint32_t>(record_length);
    return true;
}

bool Na__LazRecordWriter::Write(uint8_t* out) {
    m_impl->stream.Begin(out, m_impl->record_length);
    U32 context = 0;
    for (size_t i = 0; i < m_impl->items.size(); ++i) {
        if (!m_impl->items[i]->write(m_impl->sources[i], context)) return false;
    }
    return m_impl->stream.Ok() && m_impl->stream.Used() == m_impl->record_length;
}
