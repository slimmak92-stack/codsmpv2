// customskins_core.cpp
// Build: Visual Studio, Release, **x86 (Win32)**, "Dynamic Library (.dll)"
// Output name: customskins_core.dll  ->  put in moonloader\lib\
// Target: GTA SA 1.0 US (addresses are the same ones your Lua script used).
//
// What it does: adds NEW ped model IDs (BASE_ID..BASE_ID+MAX_SLOTS-1) and
// loads a DFF/TXD into each, so no vanilla skin (CJ etc.) is replaced.
// Lua then just calls setPlayerModel(id) with the returned id.

#include <windows.h>
#include <cstdint>
#include <cctype>
#include <cstring>
#include <string>
#include <map>

static const int BASE_ID   = 312;   // first free model id
static const int MAX_SLOTS = 8;     // raise carefully (ids must be unused)

// ---- engine function types ------------------------------------------------
typedef void* (__cdecl*  AddPedModel_t)(int);
typedef int   (__cdecl*  FindTxdSlot_t)(const char*);
typedef int   (__cdecl*  AddTxdSlot_t)(const char*);
typedef bool  (__cdecl*  LoadTxd_t)(int, const char*);
typedef void  (__cdecl*  TxdAddRef_t)(int);
typedef void  (__cdecl*  TxdSetCurrent_t)(int);
typedef void* (__cdecl*  RwStreamOpen_t)(int, int, const char*);
typedef bool  (__cdecl*  RwStreamFind_t)(void*, unsigned, unsigned*, unsigned*);
typedef void* (__cdecl*  RpClumpRead_t)(void*);
typedef bool  (__cdecl*  RwStreamClose_t)(void*, void*);
// thiscall emulated with fastcall (ecx = this, edx = dummy)
typedef void  (__fastcall* PedSetClump_t)(void*, void*, void*);

static AddPedModel_t   AddPedModel   = (AddPedModel_t)  0x4C67A0;
static FindTxdSlot_t   FindTxdSlot   = (FindTxdSlot_t)  0x731850;
static AddTxdSlot_t    AddTxdSlot    = (AddTxdSlot_t)   0x731C80;
static LoadTxd_t       LoadTxd       = (LoadTxd_t)      0x7320B0;
static TxdAddRef_t     TxdAddRef     = (TxdAddRef_t)    0x731A00;
static TxdSetCurrent_t TxdSetCurrent = (TxdSetCurrent_t)0x7319C0;
static RwStreamOpen_t  RwStreamOpen  = (RwStreamOpen_t) 0x7ECEF0;
static RwStreamFind_t  RwStreamFind  = (RwStreamFind_t) 0x7ED2D0;
static RpClumpRead_t   RpClumpRead   = (RpClumpRead_t)  0x74B420;
static RwStreamClose_t RwStreamClose = (RwStreamClose_t)0x7ECE20;
static PedSetClump_t   PedSetClump   = (PedSetClump_t)  0x4C7340;

static void** const MODEL_INFO_PTRS = (void**)0xA9B0C8; // CModelInfo::ms_modelInfoPtrs
static const uintptr_t STREAM_INFO  = 0x8E4CC0;         // CStreaming::ms_aInfoForModel (0x14 each)

enum { rwSTREAMFILENAME = 2, rwSTREAMREAD = 1, rwID_CLUMP = 0x10 };

// ---- error codes returned to Lua ------------------------------------------
enum {
    CS_OK            =  0,
    CS_ERR_ARGS      = -1,
    CS_ERR_NO_SLOTS  = -2,
    CS_ERR_TXD_SLOT  = -3,
    CS_ERR_TXD_LOAD  = -4,
    CS_ERR_ADDMODEL  = -5,
    CS_ERR_DFF_OPEN  = -6,
    CS_ERR_DFF_CLUMP = -7,
    CS_ERR_EXCEPTION = -8,
};

static int g_nextSlot = 0;
static std::map<std::string, int> g_loaded; // lowercase name -> model id

// Kept free of C++ objects so __try is allowed.
static int LoadIntoNewModel(int id, const char* dff, const char* txd,
                            const char* slotName, int basePlayerModel)
{
    __try {
        int slot = FindTxdSlot(slotName);
        if (slot == -1) slot = AddTxdSlot(slotName);
        if (slot < 0) return CS_ERR_TXD_SLOT;
        if (!LoadTxd(slot, txd)) return CS_ERR_TXD_LOAD;
        TxdAddRef(slot);

        uint8_t* info = (uint8_t*)AddPedModel(id);
        if (!info) return CS_ERR_ADDMODEL;

        // copy ped-specific fields (ped type, stat, anim group, colmodel...)
        uint8_t* base = (uint8_t*)MODEL_INFO_PTRS[basePlayerModel];
        if (base) memcpy(info + 0x28, base + 0x28, 0x1C);

        *(int16_t*)(info + 0x0A) = (int16_t)slot; // txd index

        TxdSetCurrent(slot);
        void* stream = RwStreamOpen(rwSTREAMFILENAME, rwSTREAMREAD, dff);
        if (!stream) return CS_ERR_DFF_OPEN;

        void* clump = nullptr;
        if (RwStreamFind(stream, rwID_CLUMP, nullptr, nullptr))
            clump = RpClumpRead(stream);
        RwStreamClose(stream, nullptr);
        if (!clump) return CS_ERR_DFF_CLUMP;

        PedSetClump(info, nullptr, clump);

        // mark as already loaded so the streamer never tries to read it from an IMG
        *(uint8_t*)(STREAM_INFO + (uintptr_t)id * 0x14 + 0x10) = 1;
        return CS_OK;
    }
    __except (EXCEPTION_EXECUTE_HANDLER) {
        return CS_ERR_EXCEPTION;
    }
}

// ---- exports (cdecl, undecorated) -----------------------------------------
extern "C" {

// Returns model id (>= BASE_ID) on success, or a negative CS_ERR_* code.
// Calling it again with the same name returns the cached id (no reload).
// Call from the game thread (i.e. from MoonLoader, which already is).
__declspec(dllexport) int CS_AddSkin(const char* dff, const char* txd,
                                     const char* name, int basePlayerModel)
{
    if (!dff || !txd || !name || !*name) return CS_ERR_ARGS;

    std::string key(name);
    for (auto& c : key) c = (char)tolower((unsigned char)c);

    auto it = g_loaded.find(key);
    if (it != g_loaded.end()) return it->second;

    if (g_nextSlot >= MAX_SLOTS) return CS_ERR_NO_SLOTS;

    std::string slotName = "cs_" + key;     // never collides with vanilla txds
    if (slotName.size() > 19) slotName.resize(19);

    int id = BASE_ID + g_nextSlot;
    int rc = LoadIntoNewModel(id, dff, txd, slotName.c_str(), basePlayerModel);
    if (rc != CS_OK) return rc;

    ++g_nextSlot;
    g_loaded[key] = id;
    return id;
}

__declspec(dllexport) int CS_SlotsLeft() { return MAX_SLOTS - g_nextSlot; }

} // extern "C"

BOOL APIENTRY DllMain(HMODULE, DWORD, LPVOID) { return TRUE; }
