/*
 * TOD module glue for the MicroArray MAFP fingerprint driver.
 *
 * The jdillon microarray driver is an in-tree libfprint driver that exports
 * fpi_device_microarray_get_type(). Ubuntu's libfprint is built with the TOD
 * (Touch OEM Driver) loader, which instead looks up a single well-known entry
 * point, fpi_tod_shared_driver_get_type(), in each *.so under tod-1/. This shim
 * re-exports the driver's GType under that name so it can be loaded as a TOD
 * module without replacing the system libfprint-2.so.
 */
#include <glib-object.h>
#include <gmodule.h>

extern GType fpi_device_microarray_get_type (void);

G_MODULE_EXPORT GType fpi_tod_shared_driver_get_type (void);

GType
fpi_tod_shared_driver_get_type (void)
{
  return fpi_device_microarray_get_type ();
}
